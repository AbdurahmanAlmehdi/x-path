import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

import '../../helpers/schema_dump.dart';

void main() {
  late Directory root;
  late DirectoryArtifactStore store;

  setUp(() {
    root = Directory('${tempDirectory().path}/artifacts');
    store = DirectoryArtifactStore(root.path);
  });

  Future<String> readAll(String path) async =>
      utf8.decode(await store.read(path).expand((c) => c).toList());

  test('writes the file under its job and reads it back', () async {
    await store.write(
      'job_1/dev.apk',
      Stream.fromIterable([utf8.encode('ab'), utf8.encode('c')]),
    );

    expect(File('${root.path}/job_1/dev.apk').readAsStringSync(), 'abc');
    expect(await store.exists('job_1/dev.apk'), isTrue);
    expect(await readAll('job_1/dev.apk'), 'abc');
  });

  test('replaces a file and leaves no temporary one', () async {
    await store.write('job_1/dev.apk', Stream.value(utf8.encode('one')));
    await store.write('job_1/dev.apk', Stream.value(utf8.encode('two')));

    expect(await readAll('job_1/dev.apk'), 'two');
    expect(Directory('${root.path}/job_1').listSync().map((e) => e.path), [
      '${root.path}/job_1/dev.apk',
    ]);
  });

  test('keeps the old file when a write fails', () async {
    await store.write('job_1/dev.apk', Stream.value(utf8.encode('one')));

    await expectLater(
      store.write(
        'job_1/dev.apk',
        Stream.fromFutures([
          Future.value(utf8.encode('half')),
          Future.error(StateError('disk full')),
        ]),
      ),
      throwsStateError,
    );

    expect(await readAll('job_1/dev.apk'), 'one');
    expect(Directory('${root.path}/job_1').listSync(), hasLength(1));
  });

  test('has no file that was not written', () async {
    expect(await store.exists('job_1/dev.apk'), isFalse);
    await Directory('${root.path}/job_1/folder').create(recursive: true);
    expect(await store.exists('job_1/folder'), isFalse);
  });

  test('refuses a path that is not a plain folder and name', () async {
    for (final bad in [
      'dev.apk',
      '../dev.apk',
      'job_1/../dev.apk',
      'job_1/..',
      '/job_1/dev.apk',
      'job_1//dev.apk',
      'job_1/a/b.apk',
      r'job_1\dev.apk',
      'job_1/./dev.apk',
      'job_1/dev\x00.apk',
      '',
    ]) {
      expect(
        () => store.write(bad, const Stream.empty()),
        throwsArgumentError,
        reason: bad,
      );
      expect(() => store.read(bad), throwsArgumentError, reason: bad);
      await expectLater(store.exists(bad), throwsArgumentError, reason: bad);
    }
  });
}
