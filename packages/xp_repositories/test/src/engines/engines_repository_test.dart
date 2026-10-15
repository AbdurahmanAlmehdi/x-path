import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/helpers.dart';

void main() {
  group('EngineProfile', () {
    test('round-trips through JSON', () {
      expect(EngineProfile.fromJson(remote.toJson()), remote);
      expect(remote.isLocal, isFalse);
      expect(
        EngineProfile(
          id: localEngineId,
          name: 'This Mac',
          url: localEngineUrl,
        ).isLocal,
        isTrue,
      );
    });
  });

  group('MemoryTokenVault', () {
    test('reads, writes and deletes', () async {
      final vault = MemoryTokenVault({'a': 'xpt_a'});
      expect(await vault.read('a'), 'xpt_a');
      await vault.write('b', 'xpt_b');
      expect(await vault.read('b'), 'xpt_b');
      await vault.delete('a');
      expect(await vault.read('a'), isNull);
    });
  });

  group('EngineList', () {
    final local = EngineProfile(
      id: localEngineId,
      name: 'This Mac',
      url: localEngineUrl,
    );

    test('active is the active engine, else the first, else none', () {
      expect(const EngineList().active, isNull);
      expect(EngineList(engines: [local, remote]).active, local);
      expect(
        EngineList(engines: [local, remote], activeId: remote.id).active,
        remote,
      );
      expect(
        EngineList(engines: [local, remote], activeId: 'gone').active,
        local,
      );
    });
  });

  group('parseEngineUrl', () {
    test('takes a bare host and port as http', () {
      expect(
        parseEngineUrl(' mac-mini:7480 '),
        Uri.parse('http://mac-mini:7480'),
      );
      expect(
        parseEngineUrl('https://xpath.example.com'),
        Uri.parse('https://xpath.example.com'),
      );
    });

    test('refuses what is not an http(s) URL with a host', () {
      for (final text in ['ftp://host', 'http://', 'http://[::1']) {
        expect(
          () => parseEngineUrl(text),
          throwsA(
            isA<EngineCheckException>().having(
              (error) => error.failure,
              'failure',
              EngineCheckFailure.invalidUrl,
            ),
          ),
          reason: text,
        );
      }
    });
  });

  group('EnginesRepository', () {
    late Directory directory;
    late MemoryTokenVault vault;
    late MockXpClient client;
    late List<(Uri, String)> made;
    late EnginesRepository repository;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('xp_engines_');
      vault = MemoryTokenVault();
      client = MockXpClient();
      made = [];
      repository = EnginesRepository(
        directory: p.join(directory.path, 'app'),
        vault: vault,
        clientFactory: (url, token) {
          made.add((url, token));
          return client;
        },
      );
      when(() => client.health())
          .thenAnswer((_) async => const HealthResponse());
      when(() => client.version()).thenAnswer(
        (_) async => VersionResponse(version: '0.0.1', apiVersion: apiVersion),
      );
      when(() => client.listProjects()).thenAnswer((_) async => []);
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('talks to the engine over HTTP by default', () async {
      final real = EnginesRepository(
        directory: repository.directory,
        vault: vault,
      );
      // Nothing listens on the discard port of loopback: refused at once.
      await expectLater(
        real.check(Uri.parse('http://127.0.0.1:9'), 't'),
        throwsA(
          isA<EngineCheckException>().having(
            (error) => error.failure,
            'failure',
            EngineCheckFailure.unreachable,
          ),
        ),
      );
    });

    test('knows no engine at first', () async {
      expect(await repository.load(), const EngineList());
    });

    test('reads an unreadable file as no engines', () async {
      Directory(repository.directory).createSync(recursive: true);
      File(p.join(repository.directory, 'engines.json')).writeAsStringSync('[');
      expect(await repository.load(), const EngineList());
    });

    test('saves the local engine with its token, unchecked', () async {
      final local = await repository.saveLocal(
        name: 'This Mac',
        token: 'xpt_local',
      );
      expect(local.isLocal, isTrue);
      expect(local.url, localEngineUrl);
      expect(await repository.token(localEngineId), 'xpt_local');
      expect(
        await repository.load(),
        EngineList(engines: [local], activeId: localEngineId),
      );
      expect(made, isEmpty);
    });

    test('checks and adds a remote engine, local first', () async {
      final local = await repository.saveLocal(name: 'This Mac', token: 't');
      final added = await repository.addRemote(
        name: ' mac-mini ',
        url: 'mac-mini:7480',
        token: 'xpt_remote',
      );
      expect(added, remote);
      expect(made, [(Uri.parse('http://mac-mini:7480'), 'xpt_remote')]);
      verify(() => client.close()).called(1);
      expect(await repository.token(remote.id), 'xpt_remote');
      expect(
        await repository.load(),
        EngineList(engines: [local, remote], activeId: remote.id),
      );
    });

    test(
      'names a remote engine after its host when no name is given',
      () async {
        final added = await repository.addRemote(
          name: '  ',
          url: 'http://mac-mini:7480',
          token: 't',
        );
        expect(added.name, 'mac-mini');
      },
    );

    test('replaces an engine added again at the same address', () async {
      await repository.addRemote(name: 'old', url: 'mac-mini:7480', token: 'a');
      await repository.addRemote(name: 'new', url: 'mac-mini:7480', token: 'b');
      final list = await repository.load();
      expect(list.engines.map((engine) => engine.name), ['new']);
      expect(await repository.token(remote.id), 'b');
    });

    Future<EngineCheckFailure?> failure() async {
      try {
        await repository.addRemote(name: 'x', url: 'mac-mini:7480', token: 't');
        return null;
      } on EngineCheckException catch (error) {
        expect(error.toString(), contains(error.failure.name));
        return error.failure;
      }
    }

    test('refuses an engine that does not answer', () async {
      when(() => client.health()).thenThrow(offline);
      expect(await failure(), EngineCheckFailure.unreachable);
      expect(await repository.load(), const EngineList());
      verify(() => client.close()).called(1);
    });

    test('refuses something that is not an engine', () async {
      when(() => client.health())
          .thenThrow(const ApiException('Not found.', statusCode: 404));
      expect(await failure(), EngineCheckFailure.notAnEngine);
    });

    test('refuses an engine of another API version', () async {
      when(() => client.version()).thenAnswer(
        (_) async => const VersionResponse(version: '9.0.0', apiVersion: '9'),
      );
      expect(await failure(), EngineCheckFailure.apiMismatch);
    });

    test('refuses a token the engine refuses', () async {
      when(() => client.listProjects()).thenThrow(unauthorized);
      expect(await failure(), EngineCheckFailure.tokenRejected);
      when(() => client.listProjects()).thenThrow(
        const ApiException(
          'No.',
          statusCode: 403,
          code: ApiErrorCode.forbidden,
        ),
      );
      expect(await failure(), EngineCheckFailure.tokenRejected);
    });

    test('refuses an engine that fails to list projects', () async {
      when(() => client.listProjects()).thenThrow(
        const ApiException(
          'Boom.',
          statusCode: 500,
          code: ApiErrorCode.internal,
        ),
      );
      expect(await failure(), EngineCheckFailure.notAnEngine);
    });

    test('selects and removes engines', () async {
      final local = await repository.saveLocal(name: 'This Mac', token: 't');
      await repository.addRemote(
        name: 'mac-mini',
        url: 'mac-mini:7480',
        token: 'r',
      );
      await repository.select(localEngineId);
      expect((await repository.load()).active, local);

      await repository.remove(remote.id);
      expect(await repository.token(remote.id), isNull);
      expect(
        await repository.load(),
        EngineList(engines: [local], activeId: localEngineId),
      );

      await repository.remove(localEngineId);
      expect(await repository.load(), const EngineList());
    });

    group('revokeLocalRunners', () {
      Runner runner(String id, RunnerStatus status) => Runner(
        id: id,
        name: id,
        status: status,
        capabilities: const [],
        slots: 1,
        jobIds: const [],
        createdAt: DateTime.utc(2026, 10, 16),
      );

      test('revokes the runners that are not revoked yet', () async {
        await repository.saveLocal(name: 'This Mac', token: 'xpt_local');
        when(client.listRunners).thenAnswer(
          (_) async => [
            runner('rnr_1', RunnerStatus.online),
            runner('rnr_2', RunnerStatus.revoked),
            runner('rnr_3', RunnerStatus.offline),
          ],
        );
        when(() => client.revokeRunner(any()))
            .thenAnswer((call) async => runner('x', RunnerStatus.revoked));

        expect(await repository.revokeLocalRunners(), 2);
        expect(made, [(localEngineUrl, 'xpt_local')]);
        verify(() => client.revokeRunner('rnr_1')).called(1);
        verify(() => client.revokeRunner('rnr_3')).called(1);
        verifyNever(() => client.revokeRunner('rnr_2'));
        verify(client.close).called(1);
      });

      test('does nothing without a token for the local engine', () async {
        expect(await repository.revokeLocalRunners(), 0);
        expect(made, isEmpty);
      });

      test('closes the client when the engine fails', () async {
        await repository.saveLocal(name: 'This Mac', token: 'xpt_local');
        when(client.listRunners)
            .thenThrow(const ConnectionException('refused'));

        await expectLater(
          repository.revokeLocalRunners(),
          throwsA(isA<ConnectionException>()),
        );
        verify(client.close).called(1);
      });
    });

    group('waitForLocalEngineToStop', () {
      test('waits until the engine stops answering', () async {
        var answers = 2;
        when(client.health).thenAnswer((_) async {
          if (answers-- > 0) return const HealthResponse();
          throw const ConnectionException('refused');
        });
        final waits = <Duration>[];

        final stopped = await repository.waitForLocalEngineToStop(
          delay: (duration) async => waits.add(duration),
        );

        expect(stopped, isTrue);
        expect(waits, [
          const Duration(milliseconds: 500),
          const Duration(milliseconds: 500),
        ]);
        expect(made, [(localEngineUrl, '')]);
        verify(client.close).called(1);
      });

      test('gives up after the timeout', () async {
        final waits = <Duration>[];

        final stopped = await repository.waitForLocalEngineToStop(
          timeout: const Duration(seconds: 1),
          delay: (duration) async => waits.add(duration),
        );

        expect(stopped, isFalse);
        expect(waits, hasLength(2));
      });

      test('waits for real by default', () async {
        when(client.health).thenThrow(const ConnectionException('refused'));

        expect(await repository.waitForLocalEngineToStop(), isTrue);
      });
    });
  });
}
