import 'dart:async';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/helpers.dart';

void main() {
  group('EngineStatus', () {
    test('allows commands while connected or locked only', () {
      expect(EngineStatus.values.where((status) => status.canCommand), [
        EngineStatus.connected,
        EngineStatus.secretsLocked,
      ]);
    });
  });

  group('EngineSession', () {
    late Harness harness;
    late EngineSession session;
    late List<EngineStatus> statuses;
    late int refreshes;

    setUp(() {
      harness = Harness();
      session = harness.session;
      statuses = [];
      refreshes = 0;
      session.statusChanges.listen(statuses.add);
      session.refreshes.listen((_) => refreshes++);
    });

    tearDown(() => harness.dispose());

    test('connect makes a real client and a cache folder per engine', () {
      final session = EngineSession.connect(
        profile: remote,
        token: 'xpt_1',
        cacheDirectory: '/tmp/cache',
      );
      expect(session.client.baseUrl, remote.url);
      expect(session.client.token, 'xpt_1');
      expect(
        (session.cache as FileSnapshotCache).directory,
        '/tmp/cache/mac-mini_7480',
      );
      session.client.close();
    });

    test('checks every 10 s by default', () async {
      final session = EngineSession(
        profile: remote,
        client: harness.client,
        cache: MemorySnapshotCache(),
      );
      await session.start();
      expect(session.status, EngineStatus.connected);
      await session.close();
    });

    test('connects when the engine answers', () async {
      expect(session.status, EngineStatus.connecting);
      await session.start();
      expect(session.status, EngineStatus.connected);
      await settle();
      expect(statuses, [EngineStatus.connected]);
      expect(refreshes, 0);
    });

    test('is unreachable at once when the first check fails', () async {
      when(() => harness.client.health()).thenThrow(offline);
      await session.start();
      expect(session.status, EngineStatus.unreachable);
    });

    test('reconnects, gives up, and refreshes once it is back', () async {
      await session.start();
      when(() => harness.client.health()).thenThrow(offline);

      harness.heartbeat.add(null);
      await settle();
      expect(session.status, EngineStatus.reconnecting);

      harness.heartbeat.add(null);
      await settle();
      expect(session.status, EngineStatus.unreachable);

      when(() => harness.client.health())
          .thenAnswer((_) async => const HealthResponse());
      harness.heartbeat.add(null);
      await settle();
      expect(session.status, EngineStatus.connected);
      expect(statuses, [
        EngineStatus.connected,
        EngineStatus.reconnecting,
        EngineStatus.unreachable,
        EngineStatus.connected,
      ]);
      expect(refreshes, 1);
    });

    test('takes the opening frame of the event stream as connected', () async {
      when(() => harness.client.health()).thenThrow(offline);
      await session.start();
      harness.send(const StreamOpened());
      await settle();
      expect(session.status, EngineStatus.connected);
      expect(refreshes, 1);
    });

    test('passes the events on and refreshes on a resync', () async {
      final events = <EngineEvent>[];
      session.events.listen(events.add);
      await session.start();
      harness
        ..send(const StreamOpened())
        ..send(const ProjectRemoved(projectId: 'prj_1'), seq: 2)
        ..events.add(const EventsResyncRequired());
      await settle();
      expect(events, [const ProjectRemoved(projectId: 'prj_1')]);
      expect(refreshes, 1);
    });

    test('is rejected when the engine refuses the token', () async {
      await session.start();
      harness.events.addError(unauthorized);
      await settle();
      expect(session.status, EngineStatus.rejected);

      harness.heartbeat.add(null);
      await settle();
      expect(session.status, EngineStatus.rejected, reason: 'health is open');

      session.reportSuccess();
      expect(session.status, EngineStatus.connected);
      await settle();
      expect(refreshes, 1);
    });

    test('is locked while the engine cannot read its secrets', () async {
      await session.start();
      session.reportFailure(locked);
      expect(session.status, EngineStatus.secretsLocked);
      harness.heartbeat.add(null);
      await settle();
      expect(session.status, EngineStatus.secretsLocked);

      session.reportSuccess();
      expect(session.status, EngineStatus.connected);
      await settle();
      expect(refreshes, 0);
    });

    test('ignores errors that say nothing about the connection', () async {
      await session.start();
      session
        ..reportFailure(notFound)
        ..reportFailure(StateError('bug'));
      expect(session.status, EngineStatus.connected);
    });

    test('call keeps the status up to date and passes errors on', () async {
      await session.start();
      expect(await session.call((client) async => 42), 42);
      await expectLater(
        session.call<void>((client) async => throw offline),
        throwsA(offline),
      );
      expect(session.status, EngineStatus.reconnecting);
      await session.call((client) async => 1);
      expect(session.status, EngineStatus.connected);
    });

    test('a closed session does not start', () async {
      await session.close();
      await session.start();
      expect(harness.events.hasListener, isFalse);
      verifyNever(() => harness.client.health());
    });

    test('close ends every stream and closes the client', () async {
      await session.start();
      final done = <String>[];
      session.statusChanges.listen(null, onDone: () => done.add('status'));
      session.events.listen(null, onDone: () => done.add('events'));
      session.refreshes.listen(null, onDone: () => done.add('refreshes'));

      await session.close();
      await session.close();
      await settle();

      expect(session.isClosed, isTrue);
      expect(done, ['status', 'events', 'refreshes']);
      expect(harness.events.hasListener, isFalse);
      expect(harness.heartbeat.hasListener, isFalse);
      verify(() => harness.client.close()).called(1);

      session.reportFailure(offline);
      expect(session.status, EngineStatus.connected, reason: 'frozen');
    });

    group('watch', () {
      late int fetches;
      late Future<int> Function() answer;

      Stream<Snapshot<int>> watch() => session.watch<int>(
        key: 'count',
        fetch: (client) {
          fetches++;
          return answer();
        },
        encode: (value) => {'value': value},
        decode: (json) => (json! as Map<String, dynamic>)['value'] as int,
        refreshOn: (event) => event is ProjectAdded,
      );

      setUp(() {
        fetches = 0;
        answer = () async => fetches;
      });

      test(
        'emits the cached value, then the live one, and caches it',
        () async {
          await harness.cache.write('count', {'value': 7});
          await session.start();
          final values = <Snapshot<int>>[];
          final subscription = watch().listen(values.add);
          await settle();
          expect(values, [const Snapshot(7, cached: true), const Snapshot(1)]);
          expect(await harness.cache.read('count'), {'value': 1});
          await subscription.cancel();
        },
      );

      test('loads again on its events and on a refresh', () async {
        await session.start();
        final values = <int>[];
        final subscription = watch().listen((s) => values.add(s.value));
        await settle();
        harness
          ..send(const ProjectRemoved(projectId: 'prj_1'))
          ..send(const ProjectAdded(projectId: 'prj_2', fullName: 'a/b'));
        await settle();
        harness.events.add(const EventsResyncRequired());
        await settle();
        expect(values, [1, 2, 3]);

        await subscription.cancel();
        harness.send(const ProjectAdded(projectId: 'prj_3', fullName: 'a/c'));
        await settle();
        expect(fetches, 3, reason: 'a cancelled watch stops loading');
      });

      test('folds loads that come while one runs into one more', () async {
        final gate = Completer<void>();
        answer = () async {
          if (fetches == 1) await gate.future;
          return fetches;
        };
        await session.start();
        final values = <int>[];
        final subscription = watch().listen((s) => values.add(s.value));
        await settle();
        for (var i = 0; i < 3; i++) {
          harness.send(const ProjectAdded(projectId: 'p', fullName: 'a/b'));
        }
        await settle();
        gate.complete();
        await settle();
        expect(values, [1, 2]);
        await subscription.cancel();
      });

      test('keeps the last value while the engine is away', () async {
        await harness.cache.write('count', {'value': 7});
        answer = () async => throw offline;
        await session.start();
        final values = <Snapshot<int>>[];
        final errors = <Object>[];
        final subscription = watch().listen(values.add, onError: errors.add);
        await settle();
        expect(values, [const Snapshot(7, cached: true)]);
        expect(errors, isEmpty);
        await subscription.cancel();
      });

      test(
        'emits what the engine refused (and bugs) as errors, except the status',
        () async {
          await session.start();
          final errors = <Object>[];
          answer = () async => throw locked;
          final subscription = watch().listen(null, onError: errors.add);
          await settle();
          answer = () async => throw unauthorized;
          harness.send(const ProjectAdded(projectId: 'p', fullName: 'a/b'));
          await settle();
          answer = () async => throw notFound;
          harness.send(const ProjectAdded(projectId: 'p', fullName: 'a/b'));
          await settle();
          final bug = StateError('bad answer');
          answer = () async => throw bug;
          harness.send(const ProjectAdded(projectId: 'p', fullName: 'a/b'));
          await settle();
          expect(errors, [notFound, bug]);
          await subscription.cancel();
        },
      );

      test('ends when the session closes', () async {
        final gate = Completer<void>();
        answer = () async {
          await gate.future;
          throw notFound;
        };
        await session.start();
        var done = false;
        watch().listen(null, onDone: () => done = true, onError: (_) {});
        await settle();
        await session.close();
        gate.complete();
        await settle();
        expect(done, isTrue);
      });

      test('a value that arrives after the close is dropped', () async {
        final gate = Completer<void>();
        answer = () async {
          await gate.future;
          return 5;
        };
        await session.start();
        final values = <Snapshot<int>>[];
        watch().listen(values.add);
        await settle();
        await session.close();
        gate.complete();
        await settle();
        expect(values, isEmpty);
      });

      test('ends at once when the session is closed already', () async {
        await session.start();
        await session.close();
        expect(await watch().toList(), isEmpty);
        expect(fetches, 0);
      });

      test('stops when the session closes while it reads the cache', () async {
        final cache = _SlowCache();
        final slow = EngineSession(
          profile: remote,
          client: harness.client,
          cache: cache,
          heartbeat: () => const Stream.empty(),
        );
        final values = <Snapshot<int>>[];
        var done = false;
        slow
            .watch<int>(
              key: 'count',
              fetch: (client) async => 1,
              encode: (value) => value,
              decode: (json) => json! as int,
              refreshOn: (_) => false,
            )
            .listen(values.add, onDone: () => done = true);
        await settle();
        await slow.close();
        cache.gate.complete(3);
        await settle();
        expect(values, isEmpty);
        expect(done, isTrue);
      });

      test('a cache that cannot be written does not turn the answer into '
          'an error', () async {
        final broken = EngineSession(
          profile: remote,
          client: harness.client,
          cache: _BrokenCache(),
          heartbeat: () => const Stream.empty(),
        );
        final values = <Snapshot<int>>[];
        final errors = <Object>[];
        broken
            .watch<int>(
              key: 'count',
              fetch: (client) async => 1,
              encode: (value) => value,
              decode: (json) => json! as int,
              refreshOn: (_) => false,
            )
            .listen(values.add, onError: errors.add);
        await settle();
        expect(values, [const Snapshot(1)]);
        expect(errors, isEmpty);
        await broken.close();
      });
    });
  });
}

class _BrokenCache implements SnapshotCache {
  @override
  Future<Object?> read(String key) async => null;

  @override
  Future<void> write(String key, Object? value) =>
      Future.error(const FileSystemException('Cannot rename file'));
}

class _SlowCache implements SnapshotCache {
  final gate = Completer<Object?>();

  @override
  Future<Object?> read(String key) => gate.future;

  @override
  Future<void> write(String key, Object? value) async {}
}
