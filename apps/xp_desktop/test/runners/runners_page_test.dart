import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/runners/runners.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  late MockRunnersRepository repository;
  late List<String?> clipboard;

  setUp(() {
    repository = MockRunnersRepository();
    when(repository.watchRunners).thenAnswer(
      (_) => Stream.value(
        Snapshot([busyRunner, idleRunner, lostRunner, revokedRunner]),
      ),
    );
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<RunnersBloc> pump(
    WidgetTester tester, {
    EngineStatus status = EngineStatus.connected,
  }) async {
    final bloc = RunnersBloc(runners: repository)
      ..add(const RunnersSubscriptionRequested());
    await tester.pumpApp(
      const RunnersPage(),
      runners: bloc,
      runnersRepository: repository,
      connection: connectionIn(connectedTo(status: status)),
    );
    await tester.pump();
    return bloc;
  }

  group('RunnersPage', () {
    testWidgets('lists the runners with their status, slots and jobs', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('3 runners · 1 busy'), findsOneWidget);
      expect(find.text('mac-mini'), findsOneWidget);
      expect(find.text('macos · arm64 · xp 1.0.0 · 12 cores'), findsOneWidget);
      expect(find.text('Online · busy 1/3'), findsOneWidget);
      expect(find.text('Online · idle'), findsOneWidget);
      expect(find.text('Lost mid-job'), findsOneWidget);
      expect(find.text('Not probed yet'), findsOneWidget);
      expect(find.text('ios-sign'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('job_ios'), findsOneWidget);
      expect(find.text('just now'), findsOneWidget);
      expect(find.text('2h ago'), findsOneWidget);
      expect(find.text('4m ago'), findsOneWidget);
      expect(find.text('retired'), findsOneWidget);
      expect(find.textContaining('Revoked '), findsOneWidget);
    });

    testWidgets('says when there is no runner', (tester) async {
      when(repository.watchRunners)
          .thenAnswer((_) => Stream.value(const Snapshot([])));
      await pump(tester);
      expect(find.text('No runners yet'), findsOneWidget);
    });

    testWidgets('says when a runner was never heard from', (tester) async {
      when(repository.watchRunners).thenAnswer(
        (_) => Stream.value(
          Snapshot([
            Runner(
              id: 'rnr_9',
              name: 'new-mac',
              status: RunnerStatus.offline,
              capabilities: const [],
              slots: 1,
              jobIds: const [],
              createdAt: testNow,
            ),
            Runner(
              id: 'rnr_8',
              name: 'gone',
              status: RunnerStatus.revoked,
              capabilities: const [],
              slots: 1,
              jobIds: const [],
              createdAt: testNow,
            ),
          ]),
        ),
      );
      await pump(tester);
      expect(find.text('Never'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Revoked'), findsOneWidget);
    });

    testWidgets('revokes a runner after asking', (tester) async {
      when(() => repository.revoke('rnr_1'))
          .thenAnswer((_) async => revokedRunner);
      await pump(tester);

      await tester.tap(find.text('Revoke…').first);
      await tester.pumpAndSettle();
      expect(find.text('Revoke mac-mini?'), findsOneWidget);
      expect(find.textContaining('The job it holds'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Revoke mac-mini?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.revoke(any()));

      await tester.tap(find.text('Revoke…').at(1));
      await tester.pumpAndSettle();
      expect(find.textContaining('jobs it holds'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Revoke…').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      verify(() => repository.revoke('rnr_1')).called(1);
    });

    testWidgets('shows what failed', (tester) async {
      when(() => repository.revoke('rnr_2'))
          .thenThrow(const ApiException('Only the app may.', statusCode: 403));
      final bloc = await pump(tester);
      bloc.add(const RunnerRevokeRequested('rnr_2'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Only the app may.'), findsOneWidget);
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      await pump(tester, status: EngineStatus.unreachable);
      await tester.tap(find.text('Pair runner…'));
      await tester.tap(find.text('Revoke…').first);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('PairRunnerSheet', () {
    testWidgets('makes a token and shows the command once', (tester) async {
      final completer = Completer<PairingToken>();
      when(() => repository.createPairingToken('mac-mini'))
          .thenAnswer((_) => completer.future);
      await pump(tester);

      await tester.tap(find.text('Pair runner…'));
      await tester.pumpAndSettle();
      expect(find.text('Pair a runner'), findsOneWidget);
      await tester.tap(find.text('Create pairing token'));
      await tester.pump();
      verifyNever(() => repository.createPairingToken(any()));

      await tester.enterText(find.byType(TextField), 'mac-mini');
      await tester.pump();
      await tester.tap(find.text('Create pairing token'));
      await tester.pump();
      completer.complete(
        PairingToken(
          token: 'xpp_secret',
          name: 'mac-mini',
          expiresAt: testNow.add(const Duration(minutes: 14)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pairing token for mac-mini'.toUpperCase()), findsOne);
      expect(find.text('xpp_secret'), findsOneWidget);
      const command =
          'xp runner pair --engine http://127.0.0.1:7480 --token xpp_secret';
      expect(find.text(command), findsOneWidget);
      expect(find.textContaining('expires in 14m'), findsOneWidget);

      await tester.tap(find.text('Copy command'));
      await tester.pump();
      expect(clipboard, [command]);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Pair a runner'), findsNothing);
    });

    testWidgets('warns near the end and says when it expired', (tester) async {
      final tokens = [
        PairingToken(
          token: 'xpp_1',
          name: 'a',
          expiresAt: testNow.add(const Duration(minutes: 3)),
        ),
        PairingToken(
          token: 'xpp_2',
          name: 'b',
          expiresAt: testNow.subtract(const Duration(minutes: 1)),
        ),
      ];
      when(() => repository.createPairingToken(any()))
          .thenAnswer((_) async => tokens.removeAt(0));
      await pump(tester);
      for (final name in ['a', 'b']) {
        await tester.tap(find.text('Pair runner…'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), name);
        await tester.pump();
        await tester.tap(find.text('Create pairing token'));
        await tester.pumpAndSettle();
        if (name == 'a') {
          expect(find.textContaining('expires in 3m'), findsOneWidget);
        } else {
          expect(find.textContaining('Expired.'), findsOneWidget);
        }
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('says why the engine refused, and cancels', (tester) async {
      when(() => repository.createPairingToken('mac-mini'))
          .thenThrow(const ApiException('The name is taken.', statusCode: 409));
      await pump(tester);
      await tester.tap(find.text('Pair runner…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mac-mini');
      await tester.pump();
      await tester.tap(find.text('Create pairing token'));
      await tester.pumpAndSettle();
      expect(find.text('The name is taken.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Pair a runner'), findsNothing);
    });
  });

  group('runner labels', () {
    test('a draining runner reads as updating', () {
      final draining = Runner(
        id: 'r',
        name: 'r',
        status: RunnerStatus.draining,
        capabilities: const [],
        slots: 1,
        jobIds: const [],
        createdAt: testNow,
      );
      final offline = Runner(
        id: 'o',
        name: 'o',
        status: RunnerStatus.offline,
        capabilities: const [],
        slots: 1,
        jobIds: const [],
        createdAt: testNow,
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(runnerStatus(draining), XpStatus.runnerUpdating);
      expect(runnerStatus(revokedRunner), XpStatus.runnerOffline);
      expect(runnerStatus(offline), XpStatus.runnerOffline);
      expect(runnerStatusLabel(draining, l10n), 'Draining');
      expect(runnerStatusLabel(offline, l10n), 'Offline');
      expect(runnerStatusLabel(revokedRunner, l10n), 'Revoked');
      expect(runnerMachine(offline, l10n), isEmpty);
    });
  });
}
