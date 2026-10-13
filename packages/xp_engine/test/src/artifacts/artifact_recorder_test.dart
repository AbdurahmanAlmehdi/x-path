import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

class _CountingRandom implements Random {
  var _next = 0;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();

  @override
  int nextInt(int max) => _next++ % max;
}

void main() {
  late InMemoryArtifactStore store;
  late InMemoryArtifactRepository repository;
  late ManualClock clock;
  late ArtifactRecorder recorder;

  setUp(() {
    store = InMemoryArtifactStore();
    repository = InMemoryArtifactRepository();
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    recorder = ArtifactRecorder(
      store: store,
      repository: repository,
      clock: clock,
      random: _CountingRandom(),
    );
  });

  Future<ArtifactRecord> record(String text, {String name = 'dev.apk'}) =>
      recorder.record(
        jobId: 'job_1',
        kind: ArtifactKind.apk,
        name: name,
        content: Stream.fromIterable([
          utf8.encode(text.substring(0, 1)),
          utf8.encode(text.substring(1)),
        ]),
      );

  test('stores the bytes and records their size and SHA-256', () async {
    final stored = await record('abc');

    expect(stored.path, 'job_1/dev.apk');
    expect(stored.size, 3);
    expect(
      stored.sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(stored.createdAt, DateTime.utc(2026, 10, 13, 9));
    expect(stored.pinned, isFalse);
    expect(stored.id, 'art_0001020304050607');
    expect(utf8.decode(store.files['job_1/dev.apk']!), 'abc');
    expect(await repository.get(stored.id), stored);
  });

  test('keeps one artifact per name, with its id and its pin', () async {
    final first = await record('abc');
    await repository.setPinned(first.id, pinned: true);
    clock.advance(const Duration(minutes: 5));

    final second = await record('xyz');

    expect(second.id, first.id);
    expect(second.pinned, isTrue);
    expect(second.sha256, isNot(first.sha256));
    expect(second.createdAt, DateTime.utc(2026, 10, 13, 9, 5));
    expect(await repository.forJob('job_1'), [second]);
  });

  test('gives another name another artifact', () async {
    final apk = await record('abc');
    final aab = await record('abc', name: 'dev.aab');

    expect(aab.id, isNot(apk.id));
    expect(await repository.forJob('job_1'), hasLength(2));
  });

  test('records nothing when the store fails', () async {
    final failing = ArtifactRecorder(
      store: store,
      repository: repository,
      clock: clock,
    );

    await expectLater(
      failing.record(
        jobId: 'job_1',
        kind: ArtifactKind.apk,
        name: 'dev.apk',
        content: Stream.error(StateError('disk full')),
      ),
      throwsStateError,
    );
    expect(await repository.forJob('job_1'), isEmpty);
  });

  test('names the path of a file', () {
    expect(ArtifactRecorder.pathOf('job_1', 'dev.apk'), 'job_1/dev.apk');
  });
}
