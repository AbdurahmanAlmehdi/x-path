import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/engines/engines.dart';
import 'package:xp_desktop/onboarding/onboarding.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  late MockEnginesRepository engines;
  late FakeEngineAgent agent;
  late FakeCliLinker linker;
  late FakeToolChecker tools;
  late FakeLocalEngine bundled;
  late MockEngineConnectionBloc connection;

  setUp(() {
    engines = noEngines();
    agent = FakeEngineAgent();
    linker = FakeCliLinker();
    tools = FakeToolChecker();
    bundled = FakeLocalEngine();
    connection = connectionIn(const EngineConnectionState(loaded: true));
    when(
      () => engines.saveLocal(
        name: any(named: 'name'),
        token: any(named: 'token'),
      ),
    ).thenAnswer((_) async => localEngine);
  });

  Future<void> pump(WidgetTester tester, {bool firstRun = true}) =>
      tester.pumpApp(
        OnboardingPage(firstRun: firstRun),
        connection: connection,
        services: testServices(
          engines: engines,
          agent: agent,
          linker: linker,
          tools: tools,
          localEngine: bundled,
        ),
      );

  group('OnboardingPage', () {
    testWidgets('runs the three steps and opens the app', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Set up XPath on this Mac'), findsOneWidget);
      expect(find.text('Xcode'), findsOneWidget);
      expect(find.text('/bin/xcode'), findsOneWidget);

      await tester.ensureVisible(find.text('Open XPath'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open XPath'), warnIfMissed: false);
      verifyNever(() => connection.add(const EnginesChanged()));

      await tester.tap(find.text('Start engine'));
      await tester.pumpAndSettle();
      expect(
        find.text('The engine runs and this app is connected to it.'),
        findsOneWidget,
      );
      expect(bundled.names, ['XPath app on MacBook']);
      verify(() => engines.saveLocal(name: 'This Mac', token: 'xpt_local'))
          .called(1);

      await tester.tap(find.text('Link xp'));
      await tester.pumpAndSettle();
      expect(find.text('Linked at /usr/local/bin/xp.'), findsOneWidget);

      await tester.ensureVisible(find.text('Check tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check tools'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Open XPath'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open XPath'));
      verify(() => connection.add(const EnginesChanged())).called(1);
    });

    testWidgets('asks to allow the engine in Login Items', (tester) async {
      agent.registerResult = AgentStatus.requiresApproval;
      await pump(tester);
      await tester.tap(find.text('Start engine'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Allow XPath in System Settings'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open Login Items…'));
      await tester.pumpAndSettle();
      expect(agent.settingsOpened, 1);
    });

    for (final (status, text) in [
      (AgentStatus.notFound, 'This build has no engine inside it.'),
      (AgentStatus.unsupported, 'needs macOS 13 or later'),
    ]) {
      testWidgets('says why the engine cannot run: ${status.name}', (
        tester,
      ) async {
        agent.registerResult = status;
        await pump(tester);
        await tester.tap(find.text('Start engine'));
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget);
      });
    }

    testWidgets('passes on what macOS and the engine said', (tester) async {
      agent.registerError = const MacosServiceException('x', 'Not permitted');
      await pump(tester);
      await tester.tap(find.text('Start engine'));
      await tester.pumpAndSettle();
      expect(
        find.text('macOS did not register the engine: Not permitted'),
        findsOneWidget,
      );

      agent.registerError = null;
      bundled.error = const LocalEngineException('database is locked');
      await tester.tap(find.text('Start engine'));
      await tester.pumpAndSettle();
      expect(find.textContaining('database is locked'), findsOneWidget);
    });

    for (final (link, text) in [
      (
        const CliLink(
          CliLinkState.linked,
          path: '/Users/me/.local/bin/xp',
          fellBack: true,
        ),
        'used ~/.local/bin instead',
      ),
      (const CliLink(CliLinkState.missingBinary), 'This build has no xp'),
      (
        const CliLink(CliLinkState.conflict, path: '/usr/local/bin/xp'),
        'is another xp',
      ),
      (
        const CliLink(CliLinkState.failed, detail: 'Read-only file system'),
        'Read-only file system',
      ),
    ]) {
      testWidgets('reports the link: ${link.state.name}', (tester) async {
        linker.result = link;
        await pump(tester);
        await tester.tap(find.text('Link xp'));
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget);
      });
    }

    testWidgets('lists missing tools with how to get them', (tester) async {
      tools.results = [for (final tool in Tool.values) ToolCheck(tool)];
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Missing'), findsNWidgets(2));
      expect(find.text('Optional'), findsNWidgets(3));
      for (final hint in [
        'Install Xcode from the App Store and open it once.',
        'Comes with the developer tools: xcode-select --install.',
        'Without fvm the engine downloads the Flutter each project pins.',
        'Lets the engine use your GitHub login: brew install gh.',
        'Only for over-the-air patches.',
      ]) {
        expect(find.text(hint), findsOneWidget);
      }
    });

    testWidgets('can use a remote engine instead, and come back', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Use a remote engine instead…'));
      await tester.pumpAndSettle();
      expect(find.byType(AddEngineForm), findsOneWidget);
      await tester.ensureVisible(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AddEngineForm), findsNothing);
    });

    testWidgets('is a page of the shell after the first run', (tester) async {
      await pump(tester, firstRun: false);
      expect(find.text('Set up XPath on this Mac'), findsOneWidget);
      expect(find.text('Start engine'), findsOneWidget);
    });
  });
}
