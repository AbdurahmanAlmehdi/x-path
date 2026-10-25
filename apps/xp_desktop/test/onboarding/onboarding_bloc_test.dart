import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/onboarding/bloc/onboarding_bloc.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeEngineAgent agent;
  late FakeLocalEngine bundled;
  late MockEnginesRepository engines;
  late FakeCliLinker linker;
  late FakeToolChecker tools;
  String? savedToken;

  OnboardingBloc build() => OnboardingBloc(
    agent: agent,
    localEngine: bundled,
    engines: engines,
    linker: linker,
    tools: tools,
  );

  const request = OnboardingEngineRequested(
    engineName: 'This Mac',
    tokenName: 'XPath app on MacBook',
  );

  setUp(() {
    agent = FakeEngineAgent();
    bundled = FakeLocalEngine();
    engines = MockEnginesRepository();
    linker = FakeCliLinker();
    tools = FakeToolChecker();
    savedToken = null;
    when(() => engines.token(localEngineId))
        .thenAnswer((_) async => savedToken);
    when(
      () => engines.saveLocal(
        name: any(named: 'name'),
        token: any(named: 'token'),
      ),
    ).thenAnswer((invocation) async {
      savedToken = invocation.namedArguments[#token] as String;
      return localEngine;
    });
  });

  group('OnboardingBloc', () {
    blocTest<OnboardingBloc, OnboardingState>(
      'reads where the steps stand, then checks the tools',
      build: build,
      setUp: () {
        agent.current = AgentStatus.enabled;
        savedToken = 'xpt_local';
        linker.current = const CliLink(
          CliLinkState.linked,
          path: '/usr/local/bin/xp',
        );
      },
      act: (bloc) => bloc.add(const OnboardingStarted()),
      expect: () => [
        const OnboardingState(
          engine: StepProgress.done,
          agentStatus: AgentStatus.enabled,
          cli: StepProgress.done,
          cliLink: CliLink(CliLinkState.linked, path: '/usr/local/bin/xp'),
        ),
        isA<OnboardingState>().having(
          (s) => s.tools,
          'tools',
          StepProgress.working,
        ),
        isA<OnboardingState>()
            .having((s) => s.tools, 'tools', StepProgress.done)
            .having((s) => s.toolChecks, 'checks', tools.results)
            .having((s) => s.connected, 'connected', isTrue),
      ],
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'a registered engine without a saved token is not done; nor is a '
      'Keychain that cannot be read',
      build: build,
      setUp: () {
        agent.current = AgentStatus.enabled;
        when(() => engines.token(localEngineId)).thenThrow(Exception('locked'));
      },
      act: (bloc) => bloc.add(const OnboardingStarted()),
      verify: (bloc) {
        expect(bloc.state.engine, StepProgress.idle);
        expect(bloc.state.cli, StepProgress.idle);
      },
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'starts the engine, makes the app token and saves the local engine',
      build: build,
      act: (bloc) => bloc.add(request),
      expect: () => [
        const OnboardingState(engine: StepProgress.working),
        const OnboardingState(
          engine: StepProgress.done,
          agentStatus: AgentStatus.enabled,
        ),
      ],
      verify: (_) {
        expect(agent.registrations, 1);
        expect(bundled.names, ['XPath app on MacBook']);
        verify(() => engines.saveLocal(name: 'This Mac', token: 'xpt_local'))
            .called(1);
      },
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'does not make a second token when one is saved',
      build: build,
      setUp: () => savedToken = 'xpt_saved',
      act: (bloc) => bloc.add(request),
      verify: (bloc) {
        expect(bloc.state.connected, isTrue);
        expect(bundled.names, isEmpty);
      },
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'waits for the user to allow the agent in Login Items',
      build: build,
      setUp: () => agent.registerResult = AgentStatus.requiresApproval,
      act: (bloc) => bloc
        ..add(request)
        ..add(const OnboardingLoginItemsRequested()),
      expect: () => [
        const OnboardingState(engine: StepProgress.working),
        const OnboardingState(
          engine: StepProgress.failed,
          agentStatus: AgentStatus.requiresApproval,
        ),
      ],
      verify: (_) => expect(agent.settingsOpened, 1),
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'reports what macOS refused',
      build: build,
      setUp: () => agent.registerError = const MacosServiceException(
        'register_failed',
        'Operation not permitted',
      ),
      act: (bloc) => bloc.add(request),
      skip: 1,
      expect: () => [
        const OnboardingState(
          engine: StepProgress.failed,
          engineError: 'Operation not permitted',
        ),
      ],
    );

    for (final (error, message) in [
      (const LocalEngineException('database is locked'), 'database is locked'),
      (
        const MacosServiceException('locked', 'Keychain locked'),
        'Keychain locked',
      ),
      (Exception('boom'), unexpectedErrorMessage),
    ]) {
      blocTest<OnboardingBloc, OnboardingState>(
        'reports a token that could not be made: $message',
        build: build,
        setUp: () => bundled.error = error,
        act: (bloc) => bloc.add(request),
        skip: 1,
        expect: () => [
          OnboardingState(
            engine: StepProgress.failed,
            agentStatus: AgentStatus.enabled,
            tokenError: message,
          ),
        ],
      );
    }

    blocTest<OnboardingBloc, OnboardingState>(
      'links xp',
      build: build,
      act: (bloc) => bloc.add(const OnboardingCliRequested()),
      expect: () => [
        const OnboardingState(cli: StepProgress.working),
        const OnboardingState(
          cli: StepProgress.done,
          cliLink: CliLink(CliLinkState.linked, path: '/usr/local/bin/xp'),
        ),
      ],
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'says when xp could not be linked',
      build: build,
      setUp: () => linker.result = const CliLink(CliLinkState.conflict),
      act: (bloc) => bloc.add(const OnboardingCliRequested()),
      skip: 1,
      expect: () => [
        const OnboardingState(
          cli: StepProgress.failed,
          cliLink: CliLink(CliLinkState.conflict),
        ),
      ],
    );

    blocTest<OnboardingBloc, OnboardingState>(
      'fails the tool check only for a missing required tool',
      build: build,
      setUp: () => tools.results = const [
        ToolCheck(Tool.xcode),
        ToolCheck(Tool.shorebird),
      ],
      act: (bloc) => bloc.add(const OnboardingToolsRequested()),
      skip: 1,
      expect: () => [
        const OnboardingState(
          tools: StepProgress.failed,
          toolChecks: [ToolCheck(Tool.xcode), ToolCheck(Tool.shorebird)],
        ),
      ],
    );

    test('events compare by value', () {
      expect(request.props, ['This Mac', 'XPath app on MacBook']);
      expect(const OnboardingStarted(), const OnboardingStarted());
      expect(const OnboardingStarted().props, isEmpty);
    });
  });
}
