import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import '../helpers/test_engine.dart';

void main() {
  late Directory root;
  late String dataDir;
  late WatchedSink out;
  late WatchedSink err;
  late StreamController<void> shutdown;

  Future<int> run(
    List<String> args, {
    Map<String, String> environment = const {},
    String operatingSystem = 'macos',
  }) => runXpd(
    args,
    out: out,
    err: err,
    shutdown: shutdown.stream,
    environment: environment,
    operatingSystem: operatingSystem,
  );

  // The engine database as another process would open it.
  Future<T> withDatabase<T>(
    Future<T> Function(SqliteDatabase database) action,
  ) async {
    final database = SqliteDatabase.open('$dataDir/$databaseFileName');
    try {
      return await action(database);
    } finally {
      database.close();
    }
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('xpd_cli_');
    dataDir = '${root.path}/data';
    out = WatchedSink();
    err = WatchedSink();
    shutdown = StreamController<void>.broadcast();
  });
  tearDown(() async {
    await shutdown.close();
    root.deleteSync(recursive: true);
  });

  group('runXpd', () {
    test('--version prints the version and the API version', () async {
      final code = await run(['--version']);

      expect(code, 0);
      expect(out.toString(), 'xpd $packageVersion (API v1)\n');
      expect(err.toString(), isEmpty);
    });

    test('--help prints the usage to out', () async {
      final code = await run(['--help']);

      expect(code, 0);
      expect(out.toString(), allOf(contains('serve'), contains('token')));
    });

    test('no arguments print the usage to err and fail', () async {
      final code = await run([]);

      expect(code, 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('Usage: xpd'));
    });

    test('an unknown command fails with the usage', () async {
      final code = await run(['frobnicate']);

      expect(code, 64);
      expect(err.toString(), contains('Could not find a command named'));
    });
  });

  group('xpd token create', () {
    Future<int> create(List<String> args) =>
        run(['token', 'create', '--data-dir', dataDir, ...args]);

    test('prints the token alone on out and a note on err', () async {
      final code = await create(['--name', 'Mac mini', '--kind', 'runner']);

      expect(code, 0);
      expect(out.toString(), matches(RegExp(r'^xpt_[A-Za-z0-9_-]{43}\n$')));
      expect(err.toString(), contains('runner token "Mac mini" (tok_'));
      expect(err.toString(), isNot(contains('xpt_')));
    });

    test('stores a token that authenticates, and only its hash', () async {
      await create(['-n', 'laptop', '-k', 'cli']);
      final secret = out.toString().trim();

      final token = await withDatabase(
        (database) => TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ).authenticate(secret),
      );

      expect(token?.name, 'laptop');
      expect(token?.kind, DeviceTokenKind.cli);
      for (final file in Directory(dataDir).listSync().whereType<File>()) {
        expect(
          latin1.decode(file.readAsBytesSync()),
          isNot(contains(secret)),
          reason: file.path,
        );
      }
    });

    test('keeps working on a data directory that already has tokens', () async {
      await create(['--name', 'first', '--kind', 'app']);
      await create(['--name', 'second', '--kind', 'cli']);

      final names = await withDatabase(
        (database) => SqliteDeviceTokenRepository(database).list(),
      );

      expect(names.map((token) => token.name), ['first', 'second']);
    });

    test('takes the data directory from the environment', () async {
      final code = await run(
        ['token', 'create', '--name', 'n', '--kind', 'app'],
        environment: {dataDirectoryEnvironmentKey: dataDir},
      );

      expect(code, 0);
      expect(File('$dataDir/$databaseFileName').existsSync(), isTrue);
    });

    test('xpd token --help lists create', () async {
      final code = await run(['token', '--help']);

      expect(code, 0);
      expect(out.toString(), contains('create'));
    });

    test('describes itself', () async {
      final code = await run(['token', 'create', '--help']);

      expect(code, 0);
      expect(out.toString(), contains('cannot be shown again'));
    });

    test('requires a name and a known kind', () async {
      expect(await create(['--kind', 'app']), 64);
      expect(await create(['--name', 'n']), 64);
      expect(await create(['--name', 'n', '--kind', 'robot']), 64);
      expect(out.toString(), isEmpty);
    });

    test('refuses a blank name', () async {
      final code = await create(['--name', ' ', '--kind', 'app']);

      expect(code, 64);
      expect(
        err.toString(),
        contains('--name is required and must not be blank'),
      );
    });

    test('reports a data directory that cannot be written', () async {
      File(dataDir).createSync(); // a file where the directory should be

      final code = await create(['--name', 'n', '--kind', 'app']);

      expect(code, 1);
      expect(err.toString(), startsWith('xpd: '));
      expect(out.toString(), isEmpty);
    });

    test('reports a database written by a newer xpd', () async {
      Directory(dataDir).createSync();
      SqliteDatabase.open(
        '$dataDir/$databaseFileName',
        migrations: [
          ...engineMigrations,
          Migration(version: engineMigrations.length + 1, sql: 'SELECT 1;'),
        ],
      ).close();

      final code = await create(['--name', 'n', '--kind', 'app']);

      expect(code, 1);
      expect(err.toString(), contains('newer than the'));
      expect(out.toString(), isEmpty);
    });

    test('reports a missing home directory', () async {
      final code = await run([
        'token',
        'create',
        '--name',
        'n',
        '--kind',
        'app',
      ], operatingSystem: 'linux');

      expect(code, 1);
      expect(err.toString(), contains('HOME is not set'));
    });
  });

  group('xpd serve', () {
    Future<Uri> startServing(Future<int> exit) async {
      await Future.any([out.until('listening on'), exit]);
      final match = RegExp(r'listening on (\S+)').firstMatch(out.toString());
      expect(match, isNotNull, reason: 'stdout: $out stderr: $err');
      return Uri.parse(match!.group(1)!);
    }

    test('serves on loopback until told to stop, then exits 0', () async {
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);

      expect(uri.host, '127.0.0.1');
      expect(err.toString(), isEmpty);

      shutdown.add(null);

      expect(await exit, 0);
      expect(out.toString(), contains('xpd shutting down'));
      await expectLater(
        HttpClient().getUrl(uri.resolve('/health')).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
    });

    test('under the LaunchAgent of the app, logs to a file and puts the '
        'tool folders on PATH', () async {
      final home = '${root.path}/home';
      Directory('$home/.shorebird/bin').createSync(recursive: true);
      final log = File(serveLogPath(dataDir));

      final exit = run(
        ['serve', '--port', '0', '--data-dir', dataDir],
        environment: {
          launchdEnvironmentKey: '1',
          'HOME': home,
          'PATH': '/usr/bin:/bin',
        },
      );
      while (!log.existsSync() ||
          !log.readAsStringSync().contains('listening on')) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      shutdown.add(null);

      expect(await exit, 0);
      expect(out.toString(), isEmpty);
      final written = log.readAsStringSync();
      // Homebrew's folders join it too on a Mac that has them.
      expect(
        written,
        contains('xpd runs tools with PATH=$home/.shorebird/bin:'),
      );
      expect(written, contains(':/usr/bin:/bin\n'));
      expect(written, contains('xpd shutting down'));
      expect(
        RegExp(
          r'^\d{4}-\d\d-\d\dT\S+Z xpd listening on ',
          multiLine: true,
        ).hasMatch(written),
        isTrue,
      );
    });

    test(
      'accepts tokens created while it runs and closes sockets on stop',
      () async {
        final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
        final uri = await startServing(exit);
        // Another connection, as `xpd token create` would be.
        final secret = await withDatabase(
          (database) async => (await TokenService(
            tokens: SqliteDeviceTokenRepository(database),
            clock: const SystemClock(),
          ).issue(name: 'late', kind: DeviceTokenKind.app)).secret,
        );

        final socket = await WebSocket.connect(
          'ws://127.0.0.1:${uri.port}/events',
          headers: {'authorization': 'Bearer $secret'},
        );
        final closed = Completer<int?>();
        socket.listen((_) {}, onDone: () => closed.complete(socket.closeCode));

        shutdown.add(null);

        expect(await closed.future, 1000);
        expect(await exit, 0);
      },
    );

    test('serves the projects API over the real database', () async {
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);
      final secret = await withDatabase(
        (database) async => (await TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ).issue(name: 'late', kind: DeviceTokenKind.app)).secret,
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<(int, Map<String, dynamic>)> call(
        String method,
        String path, [
        String? body,
      ]) async {
        final request = await client.openUrl(method, uri.resolve(path))
          ..headers.set('authorization', 'Bearer $secret');
        if (body != null) request.write(body);
        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      final (listed, projects) = await call('GET', '/projects');
      final (refused, _) = await call(
        'POST',
        '/projects',
        '{"remote": "https://example.com/not/github"}',
      );
      final (missing, _) = await call('GET', '/projects/prj_nope');

      expect(listed, 200);
      expect(projects['projects'], isEmpty);
      expect(refused, 400);
      expect(missing, 404);
      shutdown.add(null);
      expect(await exit, 0);
    });

    test('logs runners that connect, leave and are refused', () async {
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);
      final secret = await withDatabase(
        (database) async => (await TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ).issue(name: 'owner', kind: DeviceTokenKind.app)).secret,
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<Map<String, dynamic>> post(
        String path,
        Object body, {
        String? token,
      }) async {
        final request = await client.postUrl(uri.resolve(path));
        if (token != null) {
          request.headers.set('authorization', 'Bearer $token');
        }
        request.write(jsonEncode(body));
        final response = await request.close();
        return jsonDecode(await utf8.decodeStream(response))
            as Map<String, dynamic>;
      }

      final pairing = await post('/runners/pairing-tokens', {
        'name': 'aws',
      }, token: secret);
      final paired = await post('/runners/pair', {
        'pairingToken': pairing['token'],
      });
      final connect = 'ws://127.0.0.1:${uri.port}/runners/connect';

      await expectLater(
        WebSocket.connect(
          connect,
          headers: {'authorization': 'Bearer xpr_unknown'},
        ),
        throwsA(isA<WebSocketException>()),
      );
      await out.until('refused a runner connection');
      expect(
        out.toString(),
        contains(
          'refused a runner connection from 127.0.0.1: an unknown or revoked '
          'credential (401)\n',
        ),
      );

      final socket = await WebSocket.connect(
        connect,
        headers: {'authorization': 'Bearer ${paired['token']}'},
      );
      final frames = socket
          .map((text) => jsonDecode(text as String) as Map<String, dynamic>)
          .asBroadcastStream();
      Future<Map<String, dynamic>> next(String type) =>
          frames.firstWhere((frame) => frame['type'] == type);
      await next('welcome');
      final probe = next('probe');
      socket.add(
        jsonEncode(
          const HelloFrame(
            version: '1.0.0',
            os: 'macos',
            arch: 'arm64',
            cores: 8,
          ).toJson(),
        ),
      );
      final probeId = (await probe)['probeId'] as String;
      socket.add(
        jsonEncode(
          ProbeResultFrame(
            probeId: probeId,
            results: const [
              ProbeResult(
                id: 'os',
                status: ProbeStatus.exited,
                exitCode: 0,
                stdout: 'Darwin\n',
              ),
              ProbeResult(id: 'git', status: ProbeStatus.exited, exitCode: 0),
            ],
          ).toJson(),
        ),
      );
      await out.until('runner "aws" connected');
      expect(
        out.toString(),
        contains('runner "aws" connected: xp 1.0.0, macos arm64, 2 slots, '),
      );

      await socket.close(1000);
      await out.until('disconnected');
      expect(
        out.toString(),
        contains(
          'runner "aws" disconnected (the runner closed the connection)',
        ),
      );
      shutdown.add(null);
      expect(await exit, 0);
    });

    test('keeps the event log across a restart', () async {
      Directory(dataDir).createSync();
      final secret = await withDatabase(
        (database) async => (await TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ).issue(name: 'late', kind: DeviceTokenKind.app)).secret,
      );

      Future<List<Map<String, dynamic>>> frames(
        Uri uri,
        String query,
        int count,
      ) async {
        final socket = await WebSocket.connect(
          'ws://127.0.0.1:${uri.port}/events$query',
          headers: {'authorization': 'Bearer $secret'},
        );
        final received = await socket
            .map((frame) => jsonDecode(frame as String) as Map<String, dynamic>)
            .take(count)
            .toList();
        await socket.close();
        return received;
      }

      var exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final first = await frames(await startServing(exit), '', 1);
      shutdown.add(null);
      await exit;

      out = WatchedSink();
      exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final second = await frames(
        await startServing(exit),
        '?after=${first.single['seq']}',
        2,
      );
      shutdown.add(null);
      await exit;

      expect(first.single['type'], 'stream.opened');
      expect(first.single['seq'], 1);
      // The second run's frames: stream.opened at the new head, then what the
      // client missed: the second engine.started.
      expect(second.first['seq'], 2);
      expect(second.last['type'], 'engine.started');
      expect(second.last['seq'], 2);
    });

    test('refuses a Play target API level it cannot read', () async {
      final code = await run(
        ['serve', '--port', '0', '--data-dir', dataDir],
        environment: {'XPD_PLAY_TARGET_SDK': 'latest'},
      );

      expect(code, 1);
      expect(err.toString(), contains('XPD_PLAY_TARGET_SDK must be an API'));
      expect(out.toString(), isNot(contains('listening')));
    });

    test('says how many jobs run here and with what', () async {
      final exit = run([
        'serve',
        '--port',
        '0',
        '--slots',
        '3',
        '--data-dir',
        dataDir,
      ]);
      await startServing(exit);

      expect(out.toString(), contains('xpd runs jobs here with 3 slots and '));

      shutdown.add(null);
      await exit;
    });

    test('says what it cannot do and why', () async {
      // Only perl, which the engine needs to start: no git, no sh.
      final bin = Directory('${root.path}/bin')..createSync();
      Link(
        '${bin.path}/perl',
      ).createSync(Process.runSync('which', ['perl']).stdout.toString().trim());
      final exit = run(
        ['serve', '--port', '0', '--data-dir', dataDir],
        environment: {'PATH': bin.path},
      );
      await startServing(exit);

      expect(out.toString(), contains('and no capability\n'));
      expect(
        out.toString(),
        contains('no flutter: no git: git not found. Install git.\n'),
      );
      expect(out.toString(), contains('no android: no JDK: java not found.'));

      shutdown.add(null);
      await exit;
    });

    test(
      'counts slots in the singular, and by default a quarter of the cores',
      () async {
        final one = run([
          'serve',
          '--port',
          '0',
          '--slots',
          '1',
          '--data-dir',
          dataDir,
        ]);
        await startServing(one);
        expect(out.toString(), contains('with 1 slot and '));
        shutdown.add(null);
        await one;

        out = WatchedSink();
        final byDefault = run(['serve', '--port', '0', '--data-dir', dataDir]);
        await startServing(byDefault);
        final slots = defaultSlots(Platform.numberOfProcessors);
        expect(
          out.toString(),
          contains('with $slots slot${slots == 1 ? '' : 's'} and '),
        );
        shutdown.add(null);
        await byDefault;
      },
    );

    test(
      'rejects a number of slots that is not a whole number above zero',
      () async {
        for (final slots in ['many', '0', '-1']) {
          final code = await run([
            'serve',
            '--port',
            '0',
            '--slots',
            slots,
            '--data-dir',
            dataDir,
          ]);

          expect(code, 64, reason: slots);
          expect(err.toString(), contains('--slots must be a whole number'));
        }
      },
    );

    test('warns when it is a test engine', () async {
      final exit = run(
        ['serve', '--port', '0', '--data-dir', dataDir],
        environment: {
          TestEndpoints.fileSecretsVariable: '1',
          'PATH': Platform.environment['PATH']!,
        },
      );
      await startServing(exit);

      expect(err.toString(), contains('XPD_TEST_* is set'));

      shutdown.add(null);
      await exit;
    });

    test('serves approvals and gates over the real database', () async {
      Directory(dataDir).createSync(recursive: true);
      final now = DateTime.now().toUtc();
      ApprovalRecord approval(String id, String sha, DateTime createdAt) =>
          ApprovalRecord(
            id: id,
            projectId: 'prj_real',
            action: GateAction.prodRelease,
            sha: sha,
            version: '1.0.0+1',
            createdAt: createdAt,
            expiresAt: createdAt.add(approvalLifetime),
          );
      final tokens = await withDatabase((database) async {
        await SqliteProjectRepository(database).add(
          ProjectRecord(
            id: 'prj_real',
            host: 'github.com',
            sourceKey: '7',
            githubRepoId: 7,
            fullName: 'octo/real',
            remote: 'x',
            githubDefaultBranch: 'main',
            scan: const ProjectProfile(),
            findings: const [],
            scannedAt: DateTime.utc(2026),
          ),
        );
        final approvals = SqliteApprovalRepository(database);
        // One that ran out while the engine was off, one that has time left.
        await approvals.findOrCreate(
          approval(
            'apr_old',
            'a' * 40,
            now.subtract(approvalLifetime + const Duration(hours: 1)),
          ),
        );
        await approvals.findOrCreate(approval('apr_new', 'b' * 40, now));
        final service = TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        );
        return {
          for (final kind in DeviceTokenKind.values)
            kind: (await service.issue(name: kind.name, kind: kind)).secret,
        };
      });
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<(int, Map<String, dynamic>)> call(
        DeviceTokenKind kind,
        String method,
        String path, [
        Object? body,
      ]) async {
        final request = await client.openUrl(method, uri.resolve(path))
          ..headers.set('authorization', 'Bearer ${tokens[kind]}');
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      const app = DeviceTokenKind.app;
      const mcp = DeviceTokenKind.mcp;
      // The sweep on start expires the one that ran out.
      for (var i = 0; i < 200; i++) {
        final (_, listed) = await call(app, 'GET', '/approvals/apr_old');
        if (listed['state'] == 'expired') break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final (_, old) = await call(app, 'GET', '/approvals/apr_old');
      final (agent, _) = await call(mcp, 'POST', '/approvals/apr_new/approve');
      final (agentGates, _) = await call(
        mcp,
        'PUT',
        '/projects/prj_real/gates',
        {
          'gates': {'push': false},
        },
      );
      final (won, winner) = await call(
        app,
        'POST',
        '/approvals/apr_new/approve',
      );
      final (lost, loser) = await call(
        DeviceTokenKind.cli,
        'POST',
        '/approvals/apr_new/deny',
      );
      final (loosened, gates) = await call(
        app,
        'PUT',
        '/projects/prj_real/gates',
        {
          'gates': {'push': false},
        },
      );
      final (read, again) = await call(mcp, 'GET', '/projects/prj_real/gates');

      expect(old['state'], 'expired');
      expect(agent, 403);
      expect(agentGates, 403);
      expect(won, 200);
      expect(winner['state'], 'approved');
      expect(lost, 409);
      expect((loser['approval'] as Map)['state'], 'approved');
      expect(loosened, 200);
      expect((gates['gates'] as Map)['push'], isFalse);
      expect(read, 200);
      expect(again, gates);
      shutdown.add(null);
      expect(await exit, 0);
    });

    test('serves releases over the real database', () async {
      Directory(dataDir).createSync(recursive: true);
      final at = DateTime.now().toUtc();
      final (appToken, mcpToken) = await withDatabase((database) async {
        await SqliteProjectRepository(database).add(
          ProjectRecord(
            id: 'prj_real',
            host: 'github.com',
            sourceKey: '7',
            githubRepoId: 7,
            fullName: 'octo/real',
            remote: 'x',
            githubDefaultBranch: 'main',
            scan: const ProjectProfile(
              apps: [
                AppProfile(
                  name: 'demo',
                  path: '.',
                  flavors: [
                    FlavorProfile(
                      name: 'default',
                      entrypoint: 'lib/main.dart',
                      implicit: true,
                    ),
                  ],
                ),
              ],
            ),
            findings: const [],
            scannedAt: at,
          ),
        );
        await SqliteReleaseRepository(database).create(
          ReleaseRecord(
            id: 'rel_real',
            projectId: 'prj_real',
            appPath: '.',
            flavor: 'default',
            version: '1.2.0',
            build: 5,
            state: ReleaseState.draft,
            stores: const {},
            builds: [ReleaseBuild(build: 5, runId: 'run_1', createdAt: at)],
            baseBranch: 'main',
            createdAt: at,
            updatedAt: at,
          ),
        );
        final service = TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        );
        return (
          (await service.issue(name: 'app', kind: DeviceTokenKind.app)).secret,
          (await service.issue(name: 'mcp', kind: DeviceTokenKind.mcp)).secret,
        );
      });
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<(int, Map<String, dynamic>)> call(
        String token,
        String method,
        String path,
      ) async {
        final request = await client.openUrl(method, uri.resolve(path))
          ..headers.set('authorization', 'Bearer $token');
        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      final (listed, releases) = await call(mcpToken, 'GET', '/releases');
      final (refused, _) = await call(
        mcpToken,
        'POST',
        '/releases/rel_real/abandon',
      );
      final (abandoned, release) = await call(
        appToken,
        'POST',
        '/releases/rel_real/abandon',
      );

      expect(listed, 200);
      expect(
        ((releases['releases']! as List).single as Map<String, dynamic>)['id'],
        'rel_real',
      );
      expect(refused, 403);
      expect(abandoned, 200);
      expect(release['state'], 'abandoned');
      shutdown.add(null);
      expect(await exit, 0);
    });

    test('serves the storage report, frees up space and tells the app what '
        'matters', () async {
      Directory(dataDir).createSync(recursive: true);
      final now = DateTime.now().toUtc();
      File('$dataDir/mirrors/99.git/HEAD')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(10, 1));
      File('$dataDir/mirrors/7.git/HEAD')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(4, 1));
      final tokens = await withDatabase((database) async {
        await SqliteProjectRepository(database).add(
          ProjectRecord(
            id: 'prj_real',
            host: 'github.com',
            sourceKey: '7',
            githubRepoId: 7,
            fullName: 'octo/real',
            remote: 'x',
            githubDefaultBranch: 'main',
            scan: const ProjectProfile(),
            findings: const [],
            scannedAt: DateTime.utc(2026),
          ),
        );
        // An approval that ran out while the engine was off.
        final created = now.subtract(
          approvalLifetime + const Duration(hours: 1),
        );
        await SqliteApprovalRepository(database).findOrCreate(
          ApprovalRecord(
            id: 'apr_old',
            projectId: 'prj_real',
            action: GateAction.prodRelease,
            sha: 'a' * 40,
            version: '1.0.0+1',
            createdAt: created,
            expiresAt: created.add(approvalLifetime),
          ),
        );
        final service = TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        );
        return {
          for (final kind in DeviceTokenKind.values)
            kind: (await service.issue(name: kind.name, kind: kind)).secret,
        };
      });
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<(int, Map<String, dynamic>)> call(
        DeviceTokenKind kind,
        String method,
        String path, [
        Object? body,
      ]) async {
        final request = await client.openUrl(method, uri.resolve(path))
          ..headers.set('authorization', 'Bearer ${tokens[kind]}');
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>,
        );
      }

      // The sweep on start expired the approval; the app is told.
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${uri.port}/events?after=0',
        headers: {'authorization': 'Bearer ${tokens[DeviceTokenKind.app]}'},
      );
      final told = Completer<Map<String, dynamic>>();
      socket.listen((frame) {
        final event = jsonDecode(frame as String) as Map<String, dynamic>;
        if (event['type'] == 'notification.raised' && !told.isCompleted) {
          told.complete(event['payload'] as Map<String, dynamic>);
        }
      });
      final notification = await told.future.timeout(
        const Duration(seconds: 10),
      );

      final (reported, report) = await call(
        DeviceTokenKind.app,
        'GET',
        '/storage',
      );
      final (refused, _) = await call(
        DeviceTokenKind.mcp,
        'POST',
        '/storage/free',
        {'dryRun': false},
      );
      final (freed, result) = await call(
        DeviceTokenKind.cli,
        'POST',
        '/storage/free',
        {'dryRun': false},
      );
      // The daily pruning of logs runs at the start, but not first.
      var lastPrune = 0;
      for (var i = 0; i < 200 && lastPrune == 0; i++) {
        lastPrune = await withDatabase(
          (database) async => database.connection
              .select(
                'SELECT value FROM housekeeping_setting '
                "WHERE key = 'last_log_prune'",
              )
              .length,
        );
        if (lastPrune == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }

      expect(notification['kind'], 'approval_expired');
      expect(notification['projectId'], 'prj_real');
      expect(reported, 200);
      final mirrors = (report['categories'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['category'] == 'mirrors');
      expect(mirrors['usedBytes'], 14);
      expect(mirrors['reclaimableBytes'], 10);
      expect(refused, 403);
      expect(freed, 200);
      expect(result['dryRun'], isFalse);
      expect(Directory('$dataDir/mirrors/99.git').existsSync(), isFalse);
      expect(Directory('$dataDir/mirrors/7.git').existsSync(), isTrue);
      expect(lastPrune, 1);
      await socket.close();
      shutdown.add(null);
      expect(await exit, 0);
    });

    test('serves the workflows of a project over the real database', () async {
      Directory(dataDir).createSync(recursive: true);
      final projectId = await withDatabase((database) async {
        final record = ProjectRecord(
          id: 'prj_real',
          host: 'github.com',
          sourceKey: '7',
          githubRepoId: 7,
          fullName: 'octo/real',
          remote: '${root.path}/no-such-repository.git',
          githubDefaultBranch: 'main',
          scan: const ProjectProfile(
            apps: [
              AppProfile(
                name: 'demo',
                path: '.',
                hasAndroid: true,
                flavors: [
                  FlavorProfile(
                    name: 'default',
                    entrypoint: 'lib/main.dart',
                    implicit: true,
                  ),
                ],
              ),
            ],
          ),
          findings: const [],
          scannedAt: DateTime.utc(2026),
        );
        await SqliteProjectRepository(database).add(record);
        return record.id;
      });
      // Secrets in the encrypted file, not the Keychain: this test runs on
      // Linux too, and fetching the mirror reads the GitHub token from the
      // secret store. Only the secret store changes: as `linux`, the engine
      // would also probe `swift` before it listens, which a cold CI machine
      // can take longer than the 10 s that `startServing` waits.
      final exit = run(
        ['serve', '--port', '0', '--data-dir', dataDir],
        environment: {TestEndpoints.fileSecretsVariable: '1'},
      );
      final uri = await startServing(exit);
      final secret = await withDatabase(
        (database) async => (await TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ).issue(name: 'late', kind: DeviceTokenKind.app)).secret,
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<(int, Map<String, dynamic>)> call(
        String method,
        String path, [
        Object? body,
      ]) async {
        final request = await client.openUrl(method, uri.resolve(path))
          ..headers.set('authorization', 'Bearer $secret');
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        final text = await utf8.decodeStream(response);
        return (
          response.statusCode,
          text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>,
        );
      }

      final (listed, workflows) = await call(
        'GET',
        '/projects/$projectId/workflows',
      );
      final names = [
        for (final workflow in workflows['workflows']! as List)
          (workflow as Map)['name'],
      ];
      final (created, mine) = await call(
        'POST',
        '/projects/$projectId/workflows',
        {
          'name': 'mine',
          'yaml':
              'schema: 1\nstages:\n  - name: a\n    jobs:\n      j:\n'
              '        steps:\n          - kind: git.checkout\n',
        },
      );
      final (dispatched, run_) = await call(
        'POST',
        '/projects/$projectId/workflows/${mine['id']}/dispatch',
        {'ref': 'main'},
      );
      final (missing, _) = await call('GET', '/runs/run_nope');

      expect(listed, 200);
      expect(names, [
        'dev-build',
        'prod-release',
        'release-merge',
        'shorebird-patch',
        'test',
      ]);
      expect(created, 201);
      expect(dispatched, 502, reason: 'there is no mirror to fetch: $run_');
      expect(missing, 404);

      shutdown.add(null);
      await exit;
    });

    test('warns when the address is not loopback', () async {
      final exit = run([
        'serve',
        '--host',
        '0.0.0.0',
        '--port',
        '0',
        '--data-dir',
        dataDir,
      ]);
      await startServing(exit);

      expect(err.toString(), contains('0.0.0.0 is not a loopback address'));

      shutdown.add(null);
      await exit;
    });

    test('reports 500s on err with the details', () async {
      final exit = run(['serve', '--port', '0', '--data-dir', dataDir]);
      final uri = await startServing(exit);
      // Another connection breaks the database under the running engine.
      await withDatabase(
        (database) async =>
            database.connection.execute('DROP TABLE device_token'),
      );

      final client = HttpClient();
      final request = await client.getUrl(uri.resolve('/events'));
      request.headers.set('authorization', 'Bearer xpt_x');
      final response = await request.close();
      client.close(force: true);

      expect(response.statusCode, 500);
      expect(err.toString(), contains('error: SqliteException'));

      shutdown.add(null);
      await exit;
    });

    test('rejects a port that is not a number or out of range', () async {
      for (final port in ['http', '-1', '65536']) {
        final code = await run([
          'serve',
          '--port',
          port,
          '--data-dir',
          dataDir,
        ]);

        expect(code, 64, reason: 'port $port');
        expect(err.toString(), contains('--port must be a number'));
      }
    });

    test('reports a port that is taken', () async {
      final taken = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(taken.close);

      final code = await run([
        'serve',
        '--port',
        '${taken.port}',
        '--data-dir',
        dataDir,
      ]);

      expect(code, 1);
      expect(err.toString(), startsWith('xpd: '));
    });

    test('refuses to start without perl, which process groups need', () async {
      final empty = Directory('${root.path}/empty')..createSync();

      final code = await run(
        ['serve', '--port', '0', '--data-dir', dataDir],
        environment: {'PATH': empty.path},
      );

      expect(code, 1);
      expect(err.toString(), allOf(startsWith('xpd: '), contains('perl')));
      expect(out.toString(), isNot(contains('listening')));
    });

    group('jobs left running by an engine that stopped', () {
      final environment = {'PATH': Platform.environment['PATH']!};

      /// Seeds a job in the state a crash leaves it in: `running`, its step
      /// `running` too.
      Future<void> seedJob(
        String id,
        String executable,
        List<String> args, {
        bool sideEffect = false,
      }) async {
        Directory(dataDir).createSync(recursive: true);
        await withDatabase((database) async {
          final connection = database.connection;
          if (connection
              .select("SELECT 1 FROM workflow_version WHERE id = 'wfv_1'")
              .isEmpty) {
            connection
              ..execute(
                'INSERT INTO project (id, host, source_key, github_repo_id, '
                'remote, default_base_branch) '
                "VALUES ('prj_1', 'github.com', '1', 1, 'r', 'main')",
              )
              ..execute(
                'INSERT INTO workflow (id, project_id, name) '
                "VALUES ('wf_1', 'prj_1', 'w')",
              )
              ..execute(
                'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
                "VALUES ('wfv_1', 'wf_1', 1, '')",
              );
          }
          final plan = StepPlan.of(
            const CommandStep(),
            CommandInput(
              ProcessCommand(executable, arguments: args),
              sideEffect: sideEffect,
            ),
          );
          await SqliteJobRepository(database).create(
            JobRecord(
              id: id,
              workflowVersionId: 'wfv_1',
              projectId: 'prj_1',
              state: JobState.running,
              createdAt: DateTime.utc(2026, 10, 13),
            ),
            [
              StepRecord(
                jobId: id,
                ordinal: 0,
                kind: plan.kind,
                sideEffect: plan.sideEffect,
                input: plan.input,
                state: StepState.running,
                attempts: 1,
              ),
            ],
          );
        });
      }

      Future<Job> readJob(String id) => withDatabase((database) async {
        final repository = SqliteJobRepository(database);
        final job = (await repository.get(id))!;
        return toJob(job, await repository.steps(id));
      });

      test('are recovered: simple ones run again, risky ones wait', () async {
        await seedJob('job_plain', 'sh', ['-c', 'echo recovered']);
        await seedJob('job_risky', 'sh', [
          '-c',
          'echo never',
        ], sideEffect: true);
        final exit = run([
          'serve',
          '--port',
          '0',
          '--data-dir',
          dataDir,
        ], environment: environment);
        final uri = await startServing(exit);
        final secret = await withDatabase(
          (database) async => (await TokenService(
            tokens: SqliteDeviceTokenRepository(database),
            clock: const SystemClock(),
          ).issue(name: 'late', kind: DeviceTokenKind.app)).secret,
        );

        Future<Job> fetch(String id) async {
          final client = HttpClient();
          try {
            final request = await client.getUrl(uri.resolve('/jobs/$id'))
              ..headers.set('authorization', 'Bearer $secret');
            final response = await request.close();
            return Job.fromJson(
              jsonDecode(await utf8.decodeStream(response))
                  as Map<String, dynamic>,
            );
          } finally {
            client.close(force: true);
          }
        }

        var plain = await fetch('job_plain');
        for (var i = 0; i < 200 && plain.state != JobState.succeeded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          plain = await fetch('job_plain');
        }
        final risky = await fetch('job_risky');

        expect(plain.state, JobState.succeeded);
        expect(plain.steps.single.attempts, 2);
        expect(risky.state, JobState.waitingForResume);
        expect(risky.steps.single.state, StepState.interrupted);
        expect(out.toString(), contains('resuming interrupted job job_plain'));
        expect(err.toString(), contains('job job_risky was interrupted'));
        expect(
          File('$dataDir/logs/job_plain/0-command.log').readAsStringSync(),
          contains('recovered'),
        );

        shutdown.add(null);
        expect(await exit, 0);
      }, tags: 'process');

      test('are interrupted, not lost, when the engine stops', () async {
        // A duration no other test or run has: `pgrep` below must find only
        // the process this test started, not a `sleep 300` that an earlier
        // run (or a test of another package) left behind.
        final duration = '300.${DateTime.now().microsecondsSinceEpoch}';
        await seedJob('job_long', 'sleep', [duration]);
        final exit = run([
          'serve',
          '--port',
          '0',
          '--data-dir',
          dataDir,
        ], environment: environment);
        await startServing(exit);
        // Wait for the resumed job to be running its process.
        late Job job;
        for (var i = 0; i < 200; i++) {
          job = await readJob('job_long');
          if (job.steps.single.attempts == 2) break;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(job.steps.single.attempts, 2);

        shutdown.add(null);
        expect(await exit, 0);

        job = await readJob('job_long');
        expect(job.state, JobState.interrupted);
        expect(job.steps.single.state, StepState.interrupted);
        final left = Process.runSync('pgrep', ['-f', 'sleep $duration']);
        expect(left.exitCode, isNot(0), reason: 'the process must be gone');
      }, tags: 'process');
    });
  });
}
