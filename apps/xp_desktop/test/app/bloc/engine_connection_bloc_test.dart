import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../../helpers/fakes.dart';

void main() {
  late MockEnginesRepository engines;
  late Map<String, SessionHarness> harnesses;
  late List<(String, String)> opened;
  late EngineList list;

  EngineConnectionBloc build() => EngineConnectionBloc(
    engines: engines,
    openSession: (profile, token) {
      opened.add((profile.id, token));
      return (harnesses[profile.id] = SessionHarness(profile)).session;
    },
  );

  setUp(() {
    engines = MockEnginesRepository();
    harnesses = {};
    opened = [];
    list = EngineList(engines: [localEngine, macMini], activeId: localEngineId);
    when(() => engines.load()).thenAnswer((_) async => list);
    when(() => engines.token(any())).thenAnswer(
      (invocation) async => 'xpt_${invocation.positionalArguments.first}',
    );
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
        activeId: list.activeId == id ? null : list.activeId,
      );
    });
  });

  group('EngineConnectionBloc', () {
    test('knows nothing before it starts', () {
      final bloc = build();
      expect(bloc.state, const EngineConnectionState());
      expect(bloc.state.missingToken, isFalse);
      addTearDown(bloc.close);
    });

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'with no engine, loads an empty list and opens nothing',
      setUp: () => list = const EngineList(),
      build: build,
      act: (bloc) => bloc.add(const EngineConnectionStarted()),
      expect: () => [const EngineConnectionState(loaded: true)],
      verify: (_) => expect(opened, isEmpty),
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'opens and starts a session with the active engine and follows its '
      'status',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
      },
      expect: () => [
        isA<EngineConnectionState>()
            .having((s) => s.active, 'active', localEngine)
            .having((s) => s.status, 'status', EngineStatus.connecting)
            .having((s) => s.session, 'session', isNotNull),
        isA<EngineConnectionState>().having(
          (s) => s.status,
          'status',
          EngineStatus.connected,
        ),
      ],
      verify: (bloc) => expect(opened, [(localEngineId, 'xpt_local')]),
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'switching engines tears down the old streams and builds new ones',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        bloc.add(EngineSelected(macMini.id));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        // The new session is open and followed (closing the bloc at the end
        // of the test closes it too).
        final current = harnesses[macMini.id]!;
        expect(current.session.isClosed, isFalse);
        expect(current.events.hasListener, isTrue);
        expect(current.heartbeat.hasListener, isTrue);
        expect(bloc.state.session, same(current.session));
      },
      skip: 2,
      expect: () => [
        isA<EngineConnectionState>()
            .having((s) => s.active, 'active', macMini)
            .having((s) => s.session?.profile, 'session', macMini)
            .having((s) => s.status, 'status', EngineStatus.connecting),
        isA<EngineConnectionState>().having(
          (s) => s.status,
          'status',
          EngineStatus.connected,
        ),
      ],
      verify: (bloc) {
        final old = harnesses[localEngineId]!;
        final current = harnesses[macMini.id]!;
        // The old session is closed: its event stream and health checks are
        // cancelled, its client closed, and nothing it says reaches the bloc.
        expect(old.session.isClosed, isTrue);
        expect(old.events.hasListener, isFalse);
        expect(old.heartbeat.hasListener, isFalse);
        verify(old.client.close).called(1);
        expect(bloc.state.session, same(current.session));
        expect(opened, [
          (localEngineId, 'xpt_local'),
          (macMini.id, 'xpt_mac-mini:7480'),
        ]);
        verify(() => engines.select(macMini.id)).called(1);
      },
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'a changed engine list opens a new session even for the same engine',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        final first = harnesses[localEngineId]!.session;
        bloc.add(const EnginesChanged());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(first.isClosed, isTrue);
      },
      verify: (bloc) => expect(opened, hasLength(2)),
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'removing another engine keeps the session and still follows it',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        bloc.add(EngineRemoved(macMini.id));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(harnesses[localEngineId]!.session.isClosed, isFalse);
        harnesses[localEngineId]!.session.reportFailure(
          const ConnectionException('Connection refused.'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.status, EngineStatus.reconnecting);
      },
      verify: (bloc) {
        expect(opened, hasLength(1));
        expect(bloc.state.engines, [localEngine]);
        verify(() => engines.remove(macMini.id)).called(1);
      },
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'removing the active engine closes its session and opens the next',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const EngineRemoved(localEngineId));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      },
      verify: (bloc) {
        expect(harnesses[localEngineId]!.session.isClosed, isTrue);
        expect(bloc.state.active, macMini);
        expect(bloc.state.session?.profile, macMini);
      },
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'says the token is missing when the Keychain has none or fails',
      build: build,
      setUp: () =>
          when(() => engines.token(localEngineId))
              .thenAnswer((_) async => null),
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        when(() => engines.token(macMini.id))
            .thenThrow(const MacosServiceException('locked', 'Locked.'));
        bloc.add(EngineSelected(macMini.id));
      },
      expect: () => [
        isA<EngineConnectionState>()
            .having((s) => s.missingToken, 'missingToken', isTrue)
            .having((s) => s.status, 'status', EngineStatus.rejected),
        isA<EngineConnectionState>()
            .having((s) => s.active, 'active', macMini)
            .having((s) => s.missingToken, 'missingToken', isTrue),
      ],
      verify: (_) => expect(opened, isEmpty),
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'removing another engine while the token is missing changes the list',
      build: build,
      setUp: () =>
          when(() => engines.token(localEngineId))
              .thenAnswer((_) async => null),
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(EngineRemoved(macMini.id));
      },
      skip: 1,
      expect: () => [
        isA<EngineConnectionState>().having((s) => s.engines, 'engines', [
          localEngine,
        ]),
      ],
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'checks the engine when asked',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineConnectionStarted());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        bloc.add(const EngineCheckRequested());
        await Future<void>.delayed(Duration.zero);
      },
      verify: (_) =>
          verify(() => harnesses[localEngineId]!.client.health()).called(2),
    );

    blocTest<EngineConnectionBloc, EngineConnectionState>(
      'a check without a session does nothing',
      build: build,
      act: (bloc) => bloc.add(const EngineCheckRequested()),
      expect: () => <EngineConnectionState>[],
    );

    test('closing the bloc closes the session', () async {
      final bloc = build()..add(const EngineConnectionStarted());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await bloc.close();
      expect(harnesses[localEngineId]!.session.isClosed, isTrue);
    });

    test('events compare by value', () {
      expect(EngineSelected(macMini.id), EngineSelected(macMini.id));
      expect(const EngineRemoved('a').props, ['a']);
      expect(const EnginesChanged(), const EnginesChanged());
      expect(const EngineCheckRequested().props, isEmpty);
    });
  });
}
