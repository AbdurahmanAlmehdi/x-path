import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('PlayReleaseStatus', () {
    test('reads the API values and falls back to unknown', () {
      expect(PlayReleaseStatus.fromWire('draft'), PlayReleaseStatus.draft);
      expect(
        PlayReleaseStatus.fromWire('inProgress'),
        PlayReleaseStatus.inProgress,
      );
      expect(PlayReleaseStatus.fromWire('halted'), PlayReleaseStatus.halted);
      expect(
        PlayReleaseStatus.fromWire('completed'),
        PlayReleaseStatus.completed,
      );
      expect(PlayReleaseStatus.fromWire('new'), PlayReleaseStatus.unknown);
      expect(PlayReleaseStatus.fromWire(''), PlayReleaseStatus.unknown);
      expect(PlayReleaseStatus.fromWire(null), PlayReleaseStatus.unknown);
    });
  });

  group('PlayLifecycleState', () {
    test('reads every documented state', () {
      for (final state in PlayLifecycleState.values) {
        if (state == PlayLifecycleState.unknown) continue;
        expect(PlayLifecycleState.fromWire(state.wire), state);
      }
      expect(
        PlayLifecycleState.fromWire('RELEASE_LIFECYCLE_STATE_IN_REVIEW'),
        PlayLifecycleState.inReview,
      );
    });

    test('is unknown for the unspecified state and anything else', () {
      expect(
        PlayLifecycleState.fromWire('RELEASE_LIFECYCLE_STATE_UNSPECIFIED'),
        PlayLifecycleState.unknown,
      );
      expect(PlayLifecycleState.fromWire(null), PlayLifecycleState.unknown);
    });
  });

  test('the records compare by value', () {
    // Built from variables: equal `const` values are one object.
    final id = ['e', 'e'];
    final codes = [3, 3];
    final counts = [1, 1];
    PlayRelease release(int code) => PlayRelease(
      versionCodes: [code],
      status: PlayReleaseStatus.completed,
      releaseNotes: const {'en-US': 'Fixes'},
    );

    expect(PlayEdit(id: id[0]), PlayEdit(id: id[1]));
    expect(PlayEdit(id: id[0]), isNot(const PlayEdit(id: 'f')));
    expect(
      PlayBundle(versionCode: codes[0], sha256: 'ab'),
      PlayBundle(versionCode: codes[1], sha256: 'ab'),
    );
    expect(
      PlayBundle(versionCode: codes[0]),
      isNot(PlayBundle(versionCode: codes[1], sha256: 'ab')),
    );
    expect(
      PlayTrack(name: 'internal', releases: [release(counts[0])]),
      PlayTrack(name: 'internal', releases: [release(counts[1])]),
    );
    expect(
      PlayReleaseSummary(
        track: 't',
        state: PlayLifecycleState.published,
        versionCodes: [codes[0]],
      ),
      PlayReleaseSummary(
        track: 't',
        state: PlayLifecycleState.published,
        versionCodes: [codes[1]],
      ),
    );
  });
}
