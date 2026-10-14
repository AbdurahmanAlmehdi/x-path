import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

Map<String, dynamic> _json({Map<String, dynamic> overrides = const {}}) => {
  'artifactName': 'prod-5.4.1+3283.aab',
  'packageName': 'com.mataa.app',
  'version': '5.4.1+3283',
  'serviceAccountSecret': 'play.prod',
  ...overrides,
}..removeWhere((_, value) => value == null);

Matcher _format(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  group('UploadPlayInput', () {
    test('defaults to a completed release on the internal track', () {
      final input = UploadPlayInput.fromJson(_json());

      expect(input.track, 'internal');
      expect(input.track, defaultPlayTrack);
      expect(input.status, PlayReleaseStatus.completed);
      expect(input.versionCode, 3283);
      expect(input.userFraction, isNull);
      expect(input.releaseNotes, isEmpty);
      expect(UploadPlayInput.fromJson(input.toJson()), input);
    });

    test('names the build job whose artifact it uploads', () {
      final input = UploadPlayInput.fromJson(
        _json(overrides: {'artifactJob': 'job_build'}),
      );

      expect(input.artifactJob, 'job_build');
      expect(input.sourceOfArtifact, 'The build job job_build');
      expect(UploadPlayInput.fromJson(input.toJson()), input);
      expect(UploadPlayInput.fromJson(_json()).sourceOfArtifact, 'This job');
      expect(
        UploadPlayInput.fromJson(_json()).toJson(),
        isNot(contains('artifactJob')),
      );
    });

    test('round trips a staged rollout with notes', () {
      final json = _json(
        overrides: {
          'track': 'production',
          'status': 'inProgress',
          'userFraction': 0.1,
          'releaseName': '5.4.1',
          'releaseNotes': {'en-US': 'Fixes', 'ar': 'Fixes'},
        },
      );

      final input = UploadPlayInput.fromJson(json);

      expect(input.status, PlayReleaseStatus.inProgress);
      expect(input.userFraction, 0.1);
      expect(input.releaseNotes, {'en-US': 'Fixes', 'ar': 'Fixes'});
      expect(UploadPlayInput.fromJson(input.toJson()), input);
      expect(input.toJson()['userFraction'], 0.1);
    });

    test('takes a draft and an integer-free fraction', () {
      expect(
        UploadPlayInput.fromJson(_json(overrides: {'status': 'draft'})).status,
        PlayReleaseStatus.draft,
      );
    });

    test('needs a build number', () {
      expect(
        () => UploadPlayInput.fromJson(_json(overrides: {'version': '5.4.1'})),
        _format('build number'),
      );
    });

    test('needs a plain artifact name and a real application id', () {
      expect(
        () => UploadPlayInput.fromJson(
          _json(overrides: {'artifactName': '../a.aab'}),
        ),
        _format('plain file name'),
      );
      expect(
        () => UploadPlayInput.fromJson(
          _json(overrides: {'artifactName': r'a\b.aab'}),
        ),
        _format('plain file name'),
      );
      expect(
        () => UploadPlayInput.fromJson(
          _json(overrides: {'packageName': 'no_dots'}),
        ),
        _format('application id'),
      );
      expect(
        () => UploadPlayInput.fromJson(
          _json(overrides: {'packageName': 'a.b/../c'}),
        ),
        _format('application id'),
      );
    });

    test('needs a track name that is safe in a URL', () {
      expect(
        () => UploadPlayInput.fromJson(_json(overrides: {'track': 'a/b'})),
        _format('track name'),
      );
      expect(
        UploadPlayInput.fromJson(_json(overrides: {'track': 'wear:production'}))
            .track,
        'wear:production',
      );
    });

    test('refuses a status Play cannot take from a new bundle', () {
      expect(
        () => UploadPlayInput.fromJson(_json(overrides: {'status': 'halted'})),
        _format('"status" must be'),
      );
      expect(
        () => UploadPlayInput.fromJson(_json(overrides: {'status': 'live'})),
        _format('not live'),
      );
    });

    test('ties the user fraction to a staged rollout', () {
      expect(
        () => UploadPlayInput.fromJson(
          _json(overrides: {'status': 'inProgress'}),
        ),
        _format('"userFraction" is needed'),
      );
      expect(
        () => UploadPlayInput.fromJson(_json(overrides: {'userFraction': 0.5})),
        _format('can only be set'),
      );
      for (final bad in <Object>[0, 1, 1.5, 'half']) {
        expect(
          () => UploadPlayInput.fromJson(
            _json(overrides: {'status': 'inProgress', 'userFraction': bad}),
          ),
          _format('above 0 and below 1'),
          reason: '$bad',
        );
      }
    });

    test('needs the service account secret', () {
      expect(
        () => UploadPlayInput.fromJson(
          _json(overrides: {'serviceAccountSecret': null}),
        ),
        _format('serviceAccountSecret'),
      );
    });
  });

  test('UploadPlayResult is stored without what is unknown', () {
    expect(const UploadPlayResult(versionCode: 3, track: 'internal').toJson(), {
      'versionCode': 3,
      'track': 'internal',
      'alreadyUploaded': false,
    });
    expect(
      const UploadPlayResult(
        versionCode: 3,
        track: 'internal',
        alreadyUploaded: true,
        lifecycleState: PlayLifecycleState.inReview,
      ).toJson(),
      {
        'versionCode': 3,
        'track': 'internal',
        'alreadyUploaded': true,
        'lifecycleState': 'RELEASE_LIFECYCLE_STATE_IN_REVIEW',
      },
    );
  });
}
