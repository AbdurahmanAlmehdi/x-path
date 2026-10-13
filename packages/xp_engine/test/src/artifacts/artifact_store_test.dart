import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryArtifactStore store;

  setUp(() => store = InMemoryArtifactStore());

  test('keeps what was written and reads it back', () async {
    await store.write(
      'job_1/a.apk',
      Stream.fromIterable([
        [1, 2],
        [3],
      ]),
    );

    expect(await store.exists('job_1/a.apk'), isTrue);
    expect(await store.read('job_1/a.apk').expand((c) => c).toList(), [
      1,
      2,
      3,
    ]);
  });

  test('replaces a file', () async {
    await store.write('job_1/a.apk', Stream.value(utf8.encode('one')));
    await store.write('job_1/a.apk', Stream.value(utf8.encode('two')));

    expect(utf8.decode(store.files['job_1/a.apk']!), 'two');
  });

  test('has no file that was not written', () async {
    expect(await store.exists('job_1/a.apk'), isFalse);
    await expectLater(store.read('job_1/a.apk'), emitsError(isStateError));
  });
}
