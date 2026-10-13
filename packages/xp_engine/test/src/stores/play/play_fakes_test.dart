import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('FakeGooglePlay', () {
    late FakeGooglePlay play;

    setUp(() => play = FakeGooglePlay());

    test('opens numbered edits and records every call', () async {
      expect((await play.insertEdit('a.b')).id, 'edit-1');
      expect((await play.insertEdit('a.b')).id, 'edit-2');
      await play.deleteEdit('a.b', 'edit-1');
      await play.commitEdit('a.b', 'edit-2');

      expect(play.calls, [
        'insertEdit a.b',
        'insertEdit a.b',
        'deleteEdit a.b edit-1',
        'commitEdit a.b edit-2',
      ]);
      expect(play.deleted, ['edit-1']);
      expect(play.committed, ['edit-2']);
    });

    test('reads the bytes of an upload and counts up version codes', () async {
      Stream<List<int>> content() => Stream.fromIterable([
        [1, 2],
        [3],
      ]);

      final first = await play.uploadBundle(
        'a.b',
        'e',
        content: content,
        length: 3,
      );
      play.uploadVersionCodes.add(77);
      final second = await play.uploadBundle(
        'a.b',
        'e',
        content: content,
        length: 3,
      );

      expect(first.versionCode, 1);
      expect(second.versionCode, 77);
      expect(play.uploads, [
        [1, 2, 3],
        [1, 2, 3],
      ]);
      expect(play.uploadLengths, [3, 3]);
    });

    test('keeps the track it was given', () async {
      expect((await play.track('a.b', 'e', 'internal')).releases, isEmpty);

      const track = PlayTrack(
        name: 'internal',
        releases: [
          PlayRelease(versionCodes: [4], status: PlayReleaseStatus.completed),
        ],
      );
      await play.updateTrack('a.b', 'e', track);

      expect(await play.track('a.b', 'e', 'internal'), track);
      expect(play.updatedTracks, [track]);
    });

    test('lists bundles and releases', () async {
      play.bundlesOnPlay.add(const PlayBundle(versionCode: 9));
      play.releasesOf['internal'] = const [
        PlayReleaseSummary(
          track: 'internal',
          state: PlayLifecycleState.published,
          versionCodes: [9],
        ),
      ];

      expect(await play.bundles('a.b', 'e'), [
        const PlayBundle(versionCode: 9),
      ]);
      expect(await play.releases('a.b', 'internal'), hasLength(1));
      expect(await play.releases('a.b', 'beta'), isEmpty);
    });

    test('throws a failure once, for the call named', () async {
      play.failures['commitEdit'] = const PlayReviewInProgressException('x');

      await expectLater(
        play.commitEdit('a.b', 'e'),
        throwsA(isA<PlayReviewInProgressException>()),
      );
      await play.commitEdit('a.b', 'e');
      expect(play.committed, ['e']);
    });
  });

  test('FakePlayCredentialSource answers by application id', () async {
    const account = PlayServiceAccount(clientEmail: 'a@b.c', privateKey: 'k');
    final source = FakePlayCredentialSource({'a.b': account});

    expect(await source.forAndroidAppId('a.b'), account);
    expect(await source.forAndroidAppId('x.y'), isNull);
    expect(source.lookups, ['a.b', 'x.y']);
  });
}
