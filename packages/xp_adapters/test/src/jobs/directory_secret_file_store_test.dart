@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

int _mode(String path) => FileStat.statSync(path).mode & 0x1FF;

void main() {
  late Directory root;
  late DirectorySecretFileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_secret_files_');
    store = DirectorySecretFileStore(p.join(root.path, 'tmp'));
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test(
    'writes a file only its owner can read, in a folder only it can enter',
    () async {
      final path = await store.write('job_1', '0-KEY', 'secret\nbody');

      expect(path, p.join(root.path, 'tmp', 'job_1', '0-KEY'));
      expect(File(path).readAsStringSync(), 'secret\nbody');
      expect(_mode(path), 384, reason: '0600');
      expect(_mode(p.dirname(path)), 448, reason: '0700');
    },
  );

  test('writes binary contents byte for byte, with the same modes', () async {
    const keystore = [0xfe, 0xed, 0xfe, 0xed, 0x00, 0xff];

    final path = await store.writeBytes('job_1', '0-KS', keystore);

    expect(File(path).readAsBytesSync(), keystore);
    expect(_mode(path), 384, reason: '0600');
    expect(_mode(p.dirname(path)), 448, reason: '0700');
  });

  test('keeps several files of a job in one folder', () async {
    final a = await store.write('job_1', 'a', '1');
    final b = await store.write('job_1', 'b', '2');

    expect(p.dirname(a), p.dirname(b));
    expect(_mode(b), 384);
  });

  test('replaces a file that exists', () async {
    await store.write('job_1', 'a', 'old');
    final path = await store.write('job_1', 'a', 'new');

    expect(File(path).readAsStringSync(), 'new');
  });

  test('deletes the files of one job and no other', () async {
    final a = await store.write('job_1', 'a', '1');
    final b = await store.write('job_2', 'a', '2');

    await store.deleteAll('job_1');

    expect(File(a).existsSync(), isFalse);
    expect(Directory(p.dirname(a)).existsSync(), isFalse);
    expect(File(b).existsSync(), isTrue);
  });

  test('has nothing to delete for a job without files', () async {
    await store.deleteAll('job_none');
  });

  test('refuses a name that is not a plain file name', () async {
    for (final name in ['', '..', 'a/b', '../x', '/etc/passwd']) {
      await expectLater(
        store.write('job_1', name, 'x'),
        throwsA(isA<ArgumentError>()),
        reason: name,
      );
    }
  });

  test('fails when chmod fails, before the secret is written', () async {
    final failing = DirectorySecretFileStore(
      p.join(root.path, 'tmp'),
      runProcess: (executable, arguments) async =>
          ProcessResult(0, 1, '', 'no way'),
    );

    await expectLater(
      failing.write('job_1', 'a', 'secret'),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      File(p.join(root.path, 'tmp', 'job_1', 'a')).existsSync(),
      isFalse,
      reason: 'the directory chmod failed first',
    );
  });
}
