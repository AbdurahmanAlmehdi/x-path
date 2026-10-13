import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/job_harness.dart';
import '../../../helpers/local_artifact_store.dart';
import '../../../helpers/step_context.dart';

const _aabName = 'prod-5.4.1+3283.aab';
const _account = PlayServiceAccount(
  clientEmail: 'xpath@project.iam.gserviceaccount.com',
  privateKey: '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n',
);

UploadPlayInput _input({Map<String, dynamic> overrides = const {}}) =>
    UploadPlayInput.fromJson({
      'artifactName': _aabName,
      'packageName': 'com.mataa.app',
      'version': '5.4.1+3283',
      'serviceAccountSecret': 'play.prod',
      ...overrides,
    });

class _StoppingContext extends NoProcessContext {
  @override
  bool get isStopping => true;
}

void main() {
  late InMemoryArtifactRepository repository;
  late LocalInMemoryArtifactStore store;
  late MemorySecretStore secrets;
  late FakeGooglePlay play;
  late PlayServiceAccount? connectedWith;

  UploadPlayStep step() => UploadPlayStep(
    repository: repository,
    store: store,
    secrets: secrets,
    connect: (account) {
      connectedWith = account;
      return play;
    },
  );

  Future<void> putAab({String name = _aabName, String jobId = 'job_1'}) async {
    await ArtifactRecorder(
      store: store,
      repository: repository,
      clock: ManualClock(DateTime.utc(2026, 10, 13)),
    ).record(
      jobId: jobId,
      kind: ArtifactKind.aab,
      name: name,
      content: Stream.value(utf8.encode('aab bytes')),
    );
  }

  Future<StepOutcome<UploadPlayResult>> run([UploadPlayInput? input]) =>
      step().run(input ?? _input(), NoProcessContext());

  String message(StepOutcome<UploadPlayResult> outcome) =>
      (outcome as StepFailed).message;

  setUp(() async {
    repository = InMemoryArtifactRepository();
    store = LocalInMemoryArtifactStore();
    secrets = MemorySecretStore()..values['play.prod'] = _account.toSecret();
    play = FakeGooglePlay()..uploadVersionCodes.add(3283);
    connectedWith = null;
    await putAab();
  });

  group('the step', () {
    test('is upload.play and has a side effect', () {
      expect(step().kind, 'upload.play');
      expect(step().sideEffectOf(_input()), isTrue);
    });

    test('stores its input and result as JSON', () {
      final input = _input(overrides: {'track': 'beta'});

      expect(step().decodeInput(step().encodeInput(input)), input);
      expect(
        step().encodeResult(
          const UploadPlayResult(versionCode: 1, track: 'beta'),
        ),
        {'versionCode': 1, 'track': 'beta', 'alreadyUploaded': false},
      );
    });
  });

  group('the release', () {
    test('uploads the bundle, sets the track and commits', () async {
      play.releasesOf['internal'] = const [
        PlayReleaseSummary(
          track: 'internal',
          state: PlayLifecycleState.published,
          versionCodes: [3283],
        ),
      ];

      final outcome = await run();

      expect(connectedWith, _account);
      expect(play.calls, [
        'insertEdit com.mataa.app',
        'uploadBundle com.mataa.app edit-1 9',
        'updateTrack com.mataa.app edit-1 internal',
        'commitEdit com.mataa.app edit-1',
        'releases com.mataa.app internal',
      ]);
      expect(utf8.decode(play.uploads.single), 'aab bytes');
      expect(
        play.updatedTracks.single,
        const PlayTrack(
          name: 'internal',
          releases: [
            PlayRelease(
              versionCodes: [3283],
              status: PlayReleaseStatus.completed,
            ),
          ],
        ),
      );
      expect(
        (outcome as StepSucceeded<UploadPlayResult>).result,
        const UploadPlayResult(
          versionCode: 3283,
          track: 'internal',
          lifecycleState: PlayLifecycleState.published,
        ),
      );
      expect(play.deleted, isEmpty);
    });

    test('sends the status, fraction, name and notes of the input', () async {
      final outcome = await run(
        _input(
          overrides: {
            'track': 'production',
            'status': 'inProgress',
            'userFraction': 0.2,
            'releaseName': '5.4.1 (3283)',
            'releaseNotes': {'en-US': 'Fixes'},
          },
        ),
      );

      expect(
        play.updatedTracks.single,
        const PlayTrack(
          name: 'production',
          releases: [
            PlayRelease(
              versionCodes: [3283],
              status: PlayReleaseStatus.inProgress,
              userFraction: 0.2,
              name: '5.4.1 (3283)',
              releaseNotes: {'en-US': 'Fixes'},
            ),
          ],
        ),
      );
      expect(
        (outcome as StepSucceeded<UploadPlayResult>).result.lifecycleState,
        isNull,
      );
    });

    test('still succeeds when the review state cannot be read', () async {
      play.failures['releases'] = const PlayServerException(503, 'down');

      final outcome = await run();

      expect(outcome, isA<StepSucceeded<UploadPlayResult>>());
      expect(play.committed, ['edit-1']);
    });
  });

  group('a review in progress', () {
    test('fails the step, keeps the review and drops the edit', () async {
      play.failures['commitEdit'] = const PlayReviewInProgressException(
        'You already have changes in review.',
        reason: 'CHANGES_ALREADY_IN_REVIEW',
      );

      final outcome = await run();

      expect(
        message(outcome),
        'Play has a review in progress; the release was not committed and '
        'the review was not cancelled. Wait for the review to finish (or '
        'cancel it in the Play Console), then run the step again.',
      );
      expect(play.committed, isEmpty);
      expect(play.deleted, ['edit-1']);
    });
  });

  group('a failure', () {
    test('to open the edit says what Play said, with the fix', () async {
      play.failures['insertEdit'] = const PlayForbiddenException(
        'The caller does not have permission',
      );

      final text = message(await run());

      expect(text, contains('Google Play refused: The caller does not have'));
      expect(text, contains('invite the service account'));
      expect(play.deleted, isEmpty);
    });

    test('while uploading drops the edit', () async {
      play.failures['uploadBundle'] = const PlayVersionCodeUsedException(
        403,
        'Version code 3283 has already been used.',
      );

      final text = message(await run());

      expect(text, contains('already been used'));
      expect(text, contains('Allocate a new build number'));
      expect(play.deleted, ['edit-1']);
      expect(play.committed, isEmpty);
    });

    test('while setting the track drops the edit', () async {
      play.failures['updateTrack'] = const PlayValidationException(
        400,
        'Invalid release',
      );

      expect(message(await run()), contains('Invalid release'));
      expect(play.deleted, ['edit-1']);
    });

    test('of the edit to drop does not hide the reason', () async {
      play.failures['uploadBundle'] = const PlayServerException(500, 'boom');
      // The next failure is for deleteEdit, which runs after the upload.
      final failing = _FailingDelete(play);

      final outcome = await UploadPlayStep(
        repository: repository,
        store: store,
        secrets: secrets,
        connect: (_) => failing,
      ).run(_input(), NoProcessContext());

      expect(message(outcome), contains('boom'));
    });

    test(
      'with the wrong version code in the bundle releases nothing',
      () async {
        play.uploadVersionCodes
          ..clear()
          ..add(3000);

        final text = message(await run());

        expect(text, contains('version code 3000, not the 3283'));
        expect(play.updatedTracks, isEmpty);
        expect(play.committed, isEmpty);
        expect(play.deleted, ['edit-1']);
      },
    );

    test('of the job being cancelled stops before the commit', () async {
      final outcome = await step().run(_input(), _StoppingContext());

      expect(message(outcome), contains('cancelled before the commit'));
      expect(play.committed, isEmpty);
      expect(play.deleted, ['edit-1']);
    });
  });

  group('before the upload', () {
    test('fails without an AAB of that name in the job', () async {
      final outcome = await step().run(
        _input(overrides: {'artifactName': 'other.aab'}),
        NoProcessContext(),
      );

      expect(message(outcome), contains('no intact AAB'));
      expect(play.calls, isEmpty);
    });

    test('fails when the stored AAB changed', () async {
      store.files['job_1/$_aabName'] = utf8.encode('other bytes');

      expect(message(await run()), contains('no intact AAB'));
      expect(play.calls, isEmpty);
    });

    test('says what to do by hand when there is no service account', () async {
      secrets.values.remove('play.prod');

      final text = message(await run());

      expect(text, contains('no service account under "play.prod"'));
      expect(text, contains('upload the bundle by hand'));
      expect(play.calls, isEmpty);
    });

    test('rejects a malformed key without printing it', () async {
      secrets.values['play.prod'] = '{"client_email": "a@b.c"}';

      final text = message(await run());

      expect(text, contains('not a usable service account key'));
      expect(text, contains('private_key'));
      expect(play.calls, isEmpty);
    });
  });

  group('alreadyDone', () {
    PlayReleaseSummary summary(
      List<int> codes, {
      String track = 'internal',
      PlayLifecycleState state = PlayLifecycleState.inReview,
    }) => PlayReleaseSummary(track: track, state: state, versionCodes: codes);

    test(
      'is the release that holds the version code, with its state',
      () async {
        play.releasesOf['internal'] = [
          summary([3000]),
          summary([3282, 3283]),
        ];

        final done = await step().alreadyDone(_input(), NoProcessContext());

        expect(
          done,
          const UploadPlayResult(
            versionCode: 3283,
            track: 'internal',
            alreadyUploaded: true,
            lifecycleState: PlayLifecycleState.inReview,
          ),
        );
        expect(play.calls, ['releases com.mataa.app internal']);
      },
    );

    test('is not done for a version code the track does not have', () async {
      play.releasesOf['internal'] = [
        summary([3000]),
      ];
      play.releasesOf['production'] = [
        summary([3283], track: 'production'),
      ];

      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);
    });

    test('is not done when Play cannot be asked', () async {
      play.failures['releases'] = const PlayAuthException('revoked');
      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);

      secrets.values.remove('play.prod');
      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);

      secrets.values['play.prod'] = 'not json';
      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);
    });
  });
}

/// A client whose `deleteEdit` fails, after everything else worked as [_inner]
/// does.
class _FailingDelete implements GooglePlay {
  const new(this._inner);

  final FakeGooglePlay _inner;

  @override
  Future<void> deleteEdit(String packageName, String editId) =>
      throw const PlayServerException(503, 'cannot delete');

  @override
  Future<PlayEdit> insertEdit(String packageName) =>
      _inner.insertEdit(packageName);

  @override
  Future<PlayBundle> uploadBundle(
    String packageName,
    String editId, {
    required Stream<List<int>> Function() content,
    required int length,
  }) => _inner.uploadBundle(
    packageName,
    editId,
    content: content,
    length: length,
  );

  @override
  Future<List<PlayBundle>> bundles(String packageName, String editId) =>
      _inner.bundles(packageName, editId);

  @override
  Future<PlayTrack> track(String packageName, String editId, String track) =>
      _inner.track(packageName, editId, track);

  @override
  Future<PlayTrack> updateTrack(
    String packageName,
    String editId,
    PlayTrack track,
  ) => _inner.updateTrack(packageName, editId, track);

  @override
  Future<void> commitEdit(String packageName, String editId) =>
      _inner.commitEdit(packageName, editId);

  @override
  Future<List<PlayReleaseSummary>> releases(String packageName, String track) =>
      _inner.releases(packageName, track);

  @override
  Future<void> verifyAccess() => _inner.verifyAccess();
}
