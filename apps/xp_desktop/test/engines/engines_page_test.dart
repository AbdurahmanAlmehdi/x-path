import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/engines/engines.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  group('EnginesPage', () {
    testWidgets('lists the engines, switches and removes them', (tester) async {
      final connection = connectionIn(connectedTo());
      await tester.pumpApp(const EnginesPage(), connection: connection);
      expect(find.text('This Mac'), findsOneWidget);
      expect(find.text('http://127.0.0.1:7480'), findsOneWidget);
      expect(find.text('Showing'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Set up this Mac…'), findsNothing);

      await tester.tap(find.text('Show'));
      verify(() => connection.add(EngineSelected(macMini.id))).called(1);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove This Mac?'), findsOneWidget);
      expect(
        find.text('•  This Mac forgets This Mac and its token.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      verifyNever(() => connection.add(const EngineRemoved(localEngineId)));

      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(XpConfirmDialog),
          matching: find.text('Remove'),
        ),
      );
      await tester.pumpAndSettle();
      verify(() => connection.add(const EngineRemoved(localEngineId)))
          .called(1);
    });

    testWidgets('offers to set up this Mac without a local engine', (
      tester,
    ) async {
      final shell = ShellCubit();
      await tester.pumpApp(
        const EnginesPage(),
        shell: shell,
        connection: connectionIn(
          connectedTo(active: macMini, engines: [macMini]),
        ),
      );
      await tester.tap(find.text('Set up this Mac…'));
      expect(shell.state, const OnboardingDestination());
    });
  });

  group('AddEngineForm', () {
    late MockEnginesRepository engines;
    late MockEngineConnectionBloc connection;

    setUp(() {
      engines = noEngines();
      connection = connectionIn(connectedTo());
    });

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('addEngine.name')).last,
        'mac-mini',
      );
      await tester.enterText(
        find.byKey(const Key('addEngine.url')).last,
        'mac-mini:7480',
      );
      await tester.enterText(find.byKey(const Key('addEngine.token')), 'xpt_1');
      await tester.pump();
    }

    Finder byTextField(Key key) => find.byKey(key);

    testWidgets('adds an engine that passes the checks', (tester) async {
      when(
        () => engines.addRemote(
          name: 'mac-mini',
          url: 'mac-mini:7480',
          token: 'xpt_1',
        ),
      ).thenAnswer((_) async => macMini);
      await tester.pumpApp(
        const AddEngineForm(),
        services: testServices(engines: engines),
        connection: connection,
      );
      expect(
        find.textContaining('xpd token create --name "MacBook" --kind app'),
        findsOneWidget,
      );
      expect(byTextField(const Key('addEngine.url')), findsOneWidget);
      await tester.tap(find.text('Add engine'));
      verifyNever(
        () => engines.addRemote(
          name: any(named: 'name'),
          url: any(named: 'url'),
          token: any(named: 'token'),
        ),
      );
      await fill(tester);
      await tester.tap(find.text('Add engine'));
      await tester.pumpAndSettle();
      verify(() => connection.add(const EnginesChanged())).called(1);
    });

    for (final (failure, text) in [
      (EngineCheckFailure.invalidUrl, 'Enter an http(s) URL'),
      (EngineCheckFailure.unreachable, 'Nothing answered at that URL'),
      (EngineCheckFailure.notAnEngine, 'it is not an XPath engine'),
      (EngineCheckFailure.apiMismatch, 'another version of the API'),
      (EngineCheckFailure.tokenRejected, 'The engine refused this token'),
    ]) {
      testWidgets('says why: ${failure.name}', (tester) async {
        when(
          () => engines.addRemote(
            name: any(named: 'name'),
            url: any(named: 'url'),
            token: any(named: 'token'),
          ),
        ).thenThrow(EngineCheckException(failure));
        await tester.pumpApp(
          const AddEngineForm(),
          services: testServices(engines: engines),
          connection: connection,
        );
        await fill(tester);
        await tester.tap(find.text('Add engine'));
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget);
        verifyNever(() => connection.add(const EnginesChanged()));
      });
    }
  });
}
