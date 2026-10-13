import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xpd/xpd.dart';

ProcessResult _result(int exitCode, [String stderr = '']) =>
    ProcessResult(0, exitCode, '', stderr);

void main() {
  late Directory root;
  late String directory;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xpd_db_');
    directory = '${root.path}/data';
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('creates the directory and a migrated database', () async {
    final database = await openEngineDatabase(directory);
    addTearDown(database.close);

    expect(File('$directory/$databaseFileName').existsSync(), isTrue);
    expect(database.connection.userVersion, engineMigrations.length);
  });

  test('keeps the directory and the file private to the user', () async {
    final database = await openEngineDatabase(directory);
    addTearDown(database.close);

    expect(Directory(directory).statSync().mode & 0x1FF, 448); // 0700
    expect(
      File('$directory/$databaseFileName').statSync().mode & 0x1FF,
      384, // 0600
    );
  });

  test('opens an existing database again without touching its mode', () async {
    (await openEngineDatabase(directory)).close();
    final calls = <List<String>>[];

    final database = await openEngineDatabase(
      directory,
      runProcess: (command, args) async {
        calls.add([command, ...args]);
        return _result(0);
      },
    );
    addTearDown(database.close);

    expect(calls, isEmpty);
  });

  test('runs chmod for what it creates', () async {
    final calls = <List<String>>[];

    final database = await openEngineDatabase(
      directory,
      runProcess: (command, args) async {
        calls.add([command, ...args]);
        return _result(0);
      },
    );
    addTearDown(database.close);

    expect(calls, [
      ['chmod', '700', directory],
      ['chmod', '600', '$directory/$databaseFileName'],
    ]);
  });

  test('fails when chmod fails', () async {
    await expectLater(
      openEngineDatabase(
        directory,
        runProcess: (_, _) async => _result(1, 'no such mode'),
      ),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.message,
          'message',
          contains('chmod 700 failed: no such mode'),
        ),
      ),
    );
  });

  test('reports a database that cannot be opened', () async {
    Directory(directory).createSync();
    File('$directory/$databaseFileName').writeAsStringSync('not sqlite' * 100);

    await expectLater(
      openEngineDatabase(directory, runProcess: (_, _) async => _result(0)),
      throwsA(isA<DatabaseOpenException>()),
    );
  });
}
