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
  });
}
