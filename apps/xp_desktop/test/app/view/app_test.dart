import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  late MockEnginesRepository engines;
  late EngineList list;
  late Map<String, SessionHarness> harnesses;
  late Map<String, List<Project>> projectsOf;

  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    engines = MockEnginesRepository();
    list = EngineList(engines: [localEngine, macMini], activeId: localEngineId);
    harnesses = {};
    projectsOf = {
      localEngineId: [mataa],
      macMini.id: [captain],
    };
    when(engines.load).thenAnswer((_) async => list);
    when(() => engines.token(any())).thenAnswer((_) async => 'xpt');
    when(() => engines.select(any())).thenAnswer((invocation) async {
      list = EngineList(
        engines: list.engines,
        activeId: invocation.positionalArguments.first as String,
      );
    });
    when(() => engines.remove(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.first as String;
      list = EngineList(
        engines: [
          for (final engine in list.engines)
            if (engine.id != id) engine,
        ],
      );
    });
  });

  Future<void> pumpApp(WidgetTester tester) async {
    desktopWindow(tester);
    await tester.pumpWidget(
      App(
        services: testServices(
          engines: engines,
          openSession: (profile, token) =>
              (harnesses[profile.id] = SessionHarness(
                profile,
                projects: projectsOf[profile.id]!,
              )).session,
        ),
      ),
    );
  }

  group('App', () {
    testWidgets('starts with onboarding when it knows no engine', (
      tester,
    ) async {
      list = const EngineList();
      await pumpApp(tester);
      expect(find.byType(AppShell), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Set up XPath on this Mac'), findsOneWidget);
    });

    testWidgets('shows the shell of the active engine', (tester) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      // In the sidebar and as the overview's title.
      expect(find.text('mataa_new_app'), findsNWidgets(2));
      expect(find.text('This Mac'), findsOneWidget);
    });

    testWidgets(
      'switching engines rebuilds the repository subtree and its streams',
      (tester) async {
        await pumpApp(tester);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(AppShell));
        final oldProjects = context.read<ProjectsBloc>();
        final oldShell = context.read<ShellCubit>()
          ..show(const CredentialsDestination());
        final old = harnesses[localEngineId]!;
        expect(old.events.hasListener, isTrue);

        context.read<EngineConnectionBloc>().add(EngineSelected(macMini.id));
        await tester.pumpAndSettle();
        // The old blocs finish closing on the real event loop.
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        // The old engine's streams are gone.
        expect(old.session.isClosed, isTrue);
        expect(old.events.hasListener, isFalse);
        expect(oldProjects.isClosed, isTrue);
        expect(oldShell.isClosed, isTrue);
        // A new subtree follows the new engine.
        final next = tester.element(find.byType(AppShell));
        expect(next.read<ProjectsBloc>(), isNot(same(oldProjects)));
        expect(next.read<ShellCubit>().state, const HomeDestination());
        expect(next.read<ProjectsRepository>(), isA<ProjectsRepository>());
        expect(harnesses[macMini.id]!.events.hasListener, isTrue);
        expect(find.text('mataa_captain'), findsNWidgets(2));
        expect(find.text('mataa_new_app'), findsNothing);
        expect(find.text('mac-mini'), findsOneWidget);
      },
    );

    testWidgets('asks what to do when the token is missing', (tester) async {
      when(() => engines.token(localEngineId)).thenAnswer((_) async => null);
      await pumpApp(tester);
      await tester.pumpAndSettle();
      expect(find.text('No token for This Mac'), findsOneWidget);

      await tester.tap(find.text('Show mac-mini'));
      await tester.pumpAndSettle();
      expect(find.text('mataa_captain'), findsNWidgets(2));
    });

    testWidgets('removes an engine whose token is missing', (tester) async {
      when(() => engines.token(any())).thenAnswer((_) async => null);
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      verify(() => engines.remove(localEngineId)).called(1);
      expect(find.text('No token for mac-mini'), findsOneWidget);
    });

    testWidgets('brings the engine on this Mac back on its own at launch, '
        'with the token it has', (tester) async {
      final agent = FakeEngineAgent(current: AgentStatus.enabled);
      var running = false;
      when(() => engines.waitForLocalEngine(timeout: any(named: 'timeout')))
          .thenAnswer((invocation) async {
            final timeout = invocation.namedArguments[#timeout] as Duration;
            // Registering again (the restart) starts it.
            if (timeout > Duration.zero && agent.restarts > 0) running = true;
            return running;
          });
      when(() => engines.check(any(), any())).thenAnswer((_) async {});
      await tester.pumpWidget(
        App(
          services: testServices(
            engines: engines,
            agent: agent,
            openSession: (profile, token) {
              final harness = harnesses[profile.id] = SessionHarness(
                profile,
                projects: projectsOf[profile.id]!,
              );
              when(harness.client.health).thenAnswer((_) async {
                if (!running) throw const ConnectionException('refused');
                return const HealthResponse();
              });
              return harness.session;
            },
          ),
        ),
      );
      desktopWindow(tester);
      await tester.pumpAndSettle();

      expect(agent.restarts, 1);
      verify(() => engines.check(localEngineUrl, 'xpt')).called(1);
      verifyNever(() => engines.saveLocalToken(any()));
      final context = tester.element(find.byType(AppShell));
      expect(
        context.read<EngineConnectionBloc>().state.status,
        EngineStatus.connected,
      );
      expect(find.text('Start engine'), findsNothing);
    });
  });

  group('KeychainTokenVault', () {
    test('keeps one Keychain item per engine', () async {
      final keychain = FakeKeychain();
      final vault = KeychainTokenVault(keychain);
      await vault.write('local', 'xpt_1');
      expect(keychain.items, {'engine.local': 'xpt_1'});
      expect(await vault.read('local'), 'xpt_1');
      await vault.delete('local');
      expect(keychain.items, isEmpty);
    });

    test('a picked file compares by value', () {
      expect(
        const PickedFile(name: 'a', bytes: [1]),
        const PickedFile(name: 'a', bytes: [1]),
      );
    });
  });
}
