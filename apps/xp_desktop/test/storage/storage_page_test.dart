import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/storage/storage.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  late MockStorageRepository repository;

  setUpAll(() => registerFallbackValue(const RetentionSettings()));

  setUp(() {
    repository = MockStorageRepository();
    when(repository.watchStorage)
        .thenAnswer((_) => Stream.value(Snapshot(storageReport)));
  });

  Future<StorageBloc> pump(
    WidgetTester tester, {
    EngineStatus status = EngineStatus.connected,
  }) async {
    final bloc = StorageBloc(storage: repository)
      ..add(const StorageSubscriptionRequested());
    await tester.pumpApp(
      const StoragePage(),
      storage: bloc,
      connection: connectionIn(connectedTo(status: status)),
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa]),
      ),
    );
    await tester.pump();
    return bloc;
  }

  group('StoragePage', () {
    testWidgets('shows what the engine keeps and gives back', (tester) async {
      await pump(tester);
      expect(
        find.text(
          '${formatSizeFor(38900000000)} of ${formatSizeFor(51200000000)} '
          'reclaimable',
        ),
        findsOneWidget,
      );
      expect(find.text('Artifacts'), findsOneWidget);
      expect(find.text('Builds past the newest 5 of each flavor'), findsOne);
      expect(find.text('Logs of jobs older than 90 days'), findsOneWidget);
      expect(find.text('Flutter SDKs'), findsOneWidget);
      expect(find.text('mataa_new_app'), findsOneWidget);
      expect(find.text('prj_9'), findsOneWidget);
      expect(find.text('18 builds · 74 files'), findsOneWidget);
      expect(find.text('1 build · 2 files'), findsOneWidget);
    });

    testWidgets('frees the categories picked after asking', (tester) async {
      when(() => repository.freeSpace(any())).thenAnswer(
        (_) async => const FreeSpaceResult(
          dryRun: false,
          categories: [
            FreedCategory(
              category: StorageCategory.artifacts,
              bytes: 33100000000,
              items: 140,
            ),
            FreedCategory(category: StorageCategory.logs, bytes: 0, items: 0),
          ],
          failures: ['Could not remove a worktree.'],
        ),
      );
      await pump(tester);

      await tester.tap(find.text('Free up space…'));
      await tester.pumpAndSettle();
      expect(find.text('Free up space'), findsOneWidget);
      // Mirrors and Flutter SDKs give nothing back, so they are not offered.
      expect(find.text('Mirrors'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      verifyNever(() => repository.freeSpace(any()));

      await tester.tap(find.text('Free up space…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep everything'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Free up space…'));
      await tester.pumpAndSettle();
      for (final name in ['Artifacts', 'Logs', 'Worktrees']) {
        await tester.tap(find.widgetWithText(XpChip, name));
        await tester.pump();
      }
      final confirm = find.widgetWithText(XpButton, 'Free ${formatSizeFor(0)}');
      expect(tester.widget<XpButton>(confirm).onPressed, isNull);
      await tester.tap(find.widgetWithText(XpChip, 'Logs'));
      await tester.pump();
      await tester.tap(find.text('Free ${formatSizeFor(600000000)}'));
      await tester.pumpAndSettle();
      verify(() => repository.freeSpace([StorageCategory.logs])).called(1);
      expect(
        find.text('Freed ${formatSizeFor(33100000000)} · Artifacts 140'),
        findsOneWidget,
      );
      expect(find.text('Could not remove a worktree.'), findsOneWidget);
    });

    testWidgets('saves the retention', (tester) async {
      when(() => repository.setRetention(any()))
          .thenAnswer((_) async => const RetentionSettings(keepPerFlavor: 3));
      await pump(tester);
      final fields = find.byType(TextField);
      final save = find.widgetWithText(XpButton, 'Save');
      expect(tester.widget<XpButton>(save).onPressed, isNull);

      await tester.enterText(fields.first, '0');
      await tester.pump();
      expect(find.text('Both need a whole number of at least 1.'), findsOne);

      await tester.enterText(fields.first, '3');
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      verify(
        () =>
            repository.setRetention(const RetentionSettings(keepPerFlavor: 3)),
      ).called(1);
    });

    testWidgets('takes new retention from the engine', (tester) async {
      final bloc = await pump(tester);
      when(repository.watchStorage).thenAnswer(
        (_) => Stream.value(
          Snapshot(
            StorageReport(
              generatedAt: storageReport.generatedAt,
              categories: storageReport.categories,
              flavors: storageReport.flavors,
              retention: const RetentionSettings(keepPerFlavor: 2),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Measure again'));
      await tester.pump();
      await tester.pump();
      expect(bloc.state.report!.retention.keepPerFlavor, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '2',
      );
    });

    testWidgets('shows what failed and is read-only while away', (
      tester,
    ) async {
      when(repository.watchStorage).thenAnswer((_) async* {
        yield Snapshot(storageReport, cached: true);
        throw const ApiException('Disk gone.', statusCode: 500);
      });
      await pump(tester, status: EngineStatus.unreachable);
      expect(find.text('Disk gone.'), findsOneWidget);
      expect(
        tester
            .widget<XpButton>(find.widgetWithText(XpButton, 'Measure again'))
            .onPressed,
        isNull,
      );
      final save = find.widgetWithText(XpButton, 'Save');
      await tester.ensureVisible(save);
      expect(
        tester.widget<XpButton>(save).tooltip,
        'Read-only while the engine is away',
      );
    });
  });
}

/// [formatSize], as the page writes it.
String formatSizeFor(int bytes) => formatSize(bytes);
