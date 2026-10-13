import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

DeviceToken _token(String id, {DateTime? revokedAt}) => DeviceToken(
  id: id,
  name: 'name $id',
  kind: DeviceTokenKind.runner,
  hash: hashToken(id),
  createdAt: DateTime.utc(2026, 10, 13, 9),
  revokedAt: revokedAt,
);

void main() {
  late Directory root;
  late String directory;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xpd_tokens_');
    directory = '${root.path}/data';
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('lists nothing before the first token', () async {
    expect(await FileDeviceTokenRepository(directory).list(), isEmpty);
  });

  test('keeps tokens, revoked ones too, across instances', () async {
    final tokens = [
      _token('a'),
      _token('b', revokedAt: DateTime.utc(2026, 10, 14)),
    ];
    final writer = FileDeviceTokenRepository(directory);

    for (final token in tokens) {
      await writer.add(token);
    }

    // A second instance stands for another process, such as `xpd serve`.
    expect(await FileDeviceTokenRepository(directory).list(), tokens);
  });

  test('stores only the hash', () async {
    await FileDeviceTokenRepository(directory).add(_token('a'));

    final text = File('$directory/tokens.json').readAsStringSync();

    expect(text, contains(hashToken('a')));
    expect(text, isNot(contains('xpt_')));
  });

  test('leaves no temporary file behind', () async {
    await FileDeviceTokenRepository(directory).add(_token('a'));

    expect(
      Directory(directory).listSync().map((e) => e.uri.pathSegments.last),
      ['tokens.json'],
    );
  });

  test('makes the directory and the file private to the user', () async {
    await FileDeviceTokenRepository(directory).add(_token('a'));

    expect(Directory(directory).statSync().mode & 0x1FF, 448); // 0700
    expect(File('$directory/tokens.json').statSync().mode & 0x1FF, 384); // 0600
  }, tags: 'process');

  test('only restricts a directory it created', () async {
    final calls = <List<String>>[];
    final repository = FileDeviceTokenRepository(
      directory,
      runProcess: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        return await Process.run(executable, arguments);
      },
    );

    await repository.add(_token('a'));
    await repository.add(_token('b'));

    expect(calls.map((c) => c[1]), ['700', '600', '600']);
  });

  test('fails when the permissions cannot be set', () async {
    final repository = FileDeviceTokenRepository(
      directory,
      runProcess: (_, _) async => ProcessResult(1, 1, '', 'not permitted'),
    );

    await expectLater(
      repository.add(_token('a')),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.message,
          'message',
          contains('not permitted'),
        ),
      ),
    );
  });
}
