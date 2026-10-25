import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeEngineAgent agent;
  late FakeLocalEngine bundled;
  late MockEnginesRepository engines;
  late DateTime now;
  late List<String> logs;
  late bool answers;
  late bool answersAfterStart;

  const probe = Duration.zero;
  const startTimeout = Duration(seconds: 5);
  const start = LocalEngineStartRequested(tokenName: 'XPath app on MacBook');
  const automatic = LocalEngineStartRequested(
    tokenName: 'XPath app on MacBook',
    automatic: true,
  );

  setUpAll(() => registerFallbackValue(Uri()));

  LocalEngineBloc build({Duration maxBackoff = const Duration(minutes: 30)}) =>
      LocalEngineBloc(
        agent: agent,
        localEngine: bundled,
        engines: engines,
        now: () => now,
        log: logs.add,
        startTimeout: startTimeout,
        maxBackoff: maxBackoff,
      );

  setUp(() {
    agent = FakeEngineAgent(current: AgentStatus.enabled);
    bundled = FakeLocalEngine(token: 'xpt_new');
    engines = MockEnginesRepository();
    now = DateTime(2026, 10, 18, 9);
    logs = [];
    answers = false;
    answersAfterStart = true;
    when(() => engines.waitForLocalEngine(timeout: probe))
        .thenAnswer((_) async => answers);
    when(() => engines.waitForLocalEngine(timeout: startTimeout))
        .thenAnswer((_) async => answersAfterStart);
    when(() => engines.token(localEngineId))
        .thenAnswer((_) async => 'xpt_local');
    when(() => engines.check(any(), any())).thenAnswer((_) async {});
    when(() => engines.saveLocalToken(any())).thenAnswer((_) async {});
  });

  LocalEngineState failed(LocalEngineFailure failure, [String? message]) =>
      LocalEngineState(
        running: false,
        progress: LocalEngineProgress.failed,
        failure: failure,
        message: message,
      );

  const starting = LocalEngineState(progress: LocalEngineProgress.starting);
  const started = LocalEngineState(
    running: true,
    progress: LocalEngineProgress.started,
  );

  group('LocalEngineBloc', () {
    test('events compare by value', () {
      expect(const LocalEngineChecked().props, isEmpty);
    });

    blocTest<LocalEngineBloc, LocalEngineState>(
      'checks whether the engine answers',
      build: build,
      act: (bloc) async {
        bloc.add(const LocalEngineChecked());
        await pumpEventQueue();
        answers = true;
        bloc.add(const LocalEngineChecked());
      },
      expect: () => [
        const LocalEngineState(running: false),
        const LocalEngineState(running: true),
      ],
    );

    blocTest<LocalEngineBloc, LocalEngineState>(
      'leaves an engine that answers running and reconnects with its token',
      build: build,
      setUp: () => answers = true,
      act: (bloc) => bloc.add(start),
      expect: () => [starting, started],
      verify: (_) {
        expect(agent.restarts, 0);
        verify(() => engines.check(localEngineUrl, 'xpt_local')).called(1);
        verifyNever(() => engines.saveLocalToken(any()));
        expect(bundled.names, isEmpty);
      },
    );

    blocTest<LocalEngineBloc, LocalEngineState>(
      'restarts the login item and waits for the engine to answer',
      build: build,
      act: (bloc) => bloc.add(start),
      expect: () => [starting, started],
      verify: (_) {
        expect(agent.restarts, 1);
        verify(() => engines.waitForLocalEngine(timeout: startTimeout))
            .called(1);
        expect(logs, contains('The login item of the engine is enabled.'));
      },
    );

    blocTest<LocalEngineBloc, LocalEngineState>(
      'makes a new token only when the engine refuses the old one',
      build: build,
      setUp: () => when(
        () => engines.check(any(), any()),
      ).thenThrow(const EngineCheckException(EngineCheckFailure.tokenRejected)),
      act: (bloc) => bloc.add(start),
      expect: () => [
        starting,
        const LocalEngineState(
          running: true,
          progress: LocalEngineProgress.started,
          tokenRenewed: true,
        ),
      ],
      verify: (_) {
        expect(bundled.names, ['XPath app on MacBook']);
        verify(() => engines.saveLocalToken('xpt_new')).called(1);
      },
    );

    blocTest<LocalEngineBloc, LocalEngineState>(
      'makes a token when the app has none',
      build: build,
      setUp: () =>
          when(() => engines.token(localEngineId))
              .thenAnswer((_) async => null),
      act: (bloc) => bloc.add(start),
      expect: () => [
        starting,
        const LocalEngineState(
          running: true,
          progress: LocalEngineProgress.started,
          tokenRenewed: true,
        ),
      ],
    );

    for (final (name, stub) in [
      (
        'another check failure',
        () => when(
          () => engines.check(any(), any()),
        ).thenThrow(const EngineCheckException(EngineCheckFailure.apiMismatch)),
      ),
      (
        'a locked Keychain',
        () =>
            when(() => engines.token(localEngineId))
                .thenThrow(const MacosServiceException('locked', 'Locked.')),
      ),
    ]) {
      blocTest<LocalEngineBloc, LocalEngineState>(
        'keeps the token on $name',
        build: build,
        setUp: stub,
        act: (bloc) => bloc.add(start),
        expect: () => [starting, started],
        verify: (_) => expect(bundled.names, isEmpty),
      );
    }

    blocTest<LocalEngineBloc, LocalEngineState>(
      'says when this copy of the app has no engine',
      build: build,
      setUp: () => bundled.isBundled = false,
      act: (bloc) => bloc.add(start),
      expect: () => [starting, failed(LocalEngineFailure.noEngine)],
      verify: (_) => expect(agent.restarts, 0),
    );

    blocTest<LocalEngineBloc, LocalEngineState>(
      'says what macOS refused',
      build: build,
      setUp: () => agent.restartError = const MacosServiceException(
        'register_failed',
        'Operation not permitted',
      ),
      act: (bloc) => bloc.add(start),
      expect: () => [
        starting,
        failed(LocalEngineFailure.refused, 'Operation not permitted'),
      ],
    );

    for (final (status, failure) in [
      (AgentStatus.requiresApproval, LocalEngineFailure.needsApproval),
      (AgentStatus.unsupported, LocalEngineFailure.unsupported),
      (AgentStatus.notFound, LocalEngineFailure.noEngine),
      (AgentStatus.notRegistered, LocalEngineFailure.noEngine),
    ]) {
      blocTest<LocalEngineBloc, LocalEngineState>(
        'fails with ${failure.name} when the login item is ${status.name}',
        build: build,
        setUp: () => agent.restartResult = status,
        act: (bloc) => bloc.add(start),
        expect: () => [starting, failed(failure)],
        verify: (_) => verifyNever(
          () => engines.waitForLocalEngine(timeout: startTimeout),
        ),
      );
    }

    blocTest<LocalEngineBloc, LocalEngineState>(
      'fails when the engine does not answer in time',
      build: build,
      setUp: () => answersAfterStart = false,
      act: (bloc) => bloc.add(start),
      expect: () => [starting, failed(LocalEngineFailure.timedOut)],
    );

    for (final (name, error, message) in [
      (
        'the engine',
        const LocalEngineException('database is locked'),
        'database is locked',
      ),
      (
        'the Keychain',
        const MacosServiceException('keychain', 'No access.'),
        'No access.',
      ),
      ('anything else', Exception('boom'), unexpectedErrorMessage),
    ]) {
      blocTest<LocalEngineBloc, LocalEngineState>(
        'says why there is no new token: $name',
        build: build,
        setUp: () {
          when(() => engines.token(localEngineId))
              .thenAnswer((_) async => null);
          when(() => engines.saveLocalToken(any())).thenThrow(error);
        },
        act: (bloc) => bloc.add(start),
        expect: () => [starting, failed(LocalEngineFailure.token, message)],
      );
    }

    blocTest<LocalEngineBloc, LocalEngineState>(
      'answers a check during a start with nothing',
      build: build,
      act: (bloc) async {
        final up = Completer<bool>();
        when(() => engines.waitForLocalEngine(timeout: startTimeout))
            .thenAnswer((_) => up.future);
        bloc.add(start);
        await pumpEventQueue();
        bloc.add(const LocalEngineChecked());
        await pumpEventQueue();
        up.complete(true);
      },
      expect: () => [starting, started],
    );

    blocTest<LocalEngineBloc, LocalEngineState>(
      'opens Login Items',
      build: build,
      act: (bloc) => bloc.add(const LocalEngineLoginItemsRequested()),
      verify: (_) => expect(agent.settingsOpened, 1),
    );

    group('on its own', () {
      blocTest<LocalEngineBloc, LocalEngineState>(
        'tries once per episode',
        build: build,
        setUp: () => answersAfterStart = false,
        act: (bloc) async {
          bloc.add(automatic);
          await pumpEventQueue();
          now = now.add(const Duration(hours: 1));
          bloc.add(automatic);
        },
        expect: () => [starting, failed(LocalEngineFailure.timedOut)],
        verify: (_) {
          expect(agent.restarts, 1);
          expect(logs.first, contains('starting it'));
          expect(logs.last, contains('tried once already'));
        },
      );

      blocTest<LocalEngineBloc, LocalEngineState>(
        'waits longer after each failed try, up to the most',
        build: () => build(maxBackoff: const Duration(minutes: 3)),
        setUp: () => answersAfterStart = false,
        act: (bloc) async {
          Future<void> episode(Duration later) async {
            now = now.add(later);
            bloc
              ..add(const LocalEngineReachable())
              ..add(automatic);
            await pumpEventQueue();
          }

          await episode(Duration.zero); // tries; next after 2 min
          await episode(const Duration(minutes: 1)); // too soon
          await episode(const Duration(minutes: 1)); // tries; next after 3
          await episode(const Duration(minutes: 2)); // too soon
          await episode(const Duration(minutes: 1)); // tries
        },
        verify: (_) {
          expect(agent.restarts, 3);
          expect(
            logs.where((line) => line.contains('less than 2 min')),
            hasLength(1),
          );
          expect(
            logs.where((line) => line.contains('less than 3 min')),
            hasLength(1),
          );
        },
      );

      blocTest<LocalEngineBloc, LocalEngineState>(
        'waits the shortest time again after a try that worked',
        build: build,
        act: (bloc) async {
          bloc.add(automatic);
          await pumpEventQueue();
          now = now.add(const Duration(minutes: 1));
          bloc
            ..add(const LocalEngineReachable())
            ..add(automatic);
        },
        expect: () => [
          starting,
          started,
          const LocalEngineState(running: true),
          const LocalEngineState(
            running: true,
            progress: LocalEngineProgress.starting,
          ),
          started,
        ],
        verify: (_) => expect(agent.restarts, 2),
      );

      test('logs with dart:developer by default', () async {
        answers = true;
        final bloc = LocalEngineBloc(
          agent: agent,
          localEngine: bundled,
          engines: engines,
        )..add(automatic);
        await pumpEventQueue();
        expect(bloc.state, started);
        await bloc.close();
      });
    });
  });
}
