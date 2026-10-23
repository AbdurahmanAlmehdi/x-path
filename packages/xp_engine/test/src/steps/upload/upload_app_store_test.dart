import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/altool_fixtures.dart';
import '../../../helpers/job_harness.dart';
import '../../../helpers/local_artifact_store.dart';
import '../../../helpers/streaming_context.dart';

const _ipaName = 'prod-5.4.1+3283.ipa';
const _password = 'abcd-efgh-ijkl-mnop';
const _key = AscKey(
  keyId: 'ABC123DEF4',
  issuerId: '57246542-96fe-1a63-e053-0824d011072a',
  privateKey: '-----BEGIN PRIVATE KEY-----\nMIG\n-----END PRIVATE KEY-----\n',
);

UploadAppStoreInput _input({AppStoreUploadAuth? auth}) =>
    UploadAppStoreInput.fromJson({
      'artifactName': _ipaName,
      'bundleId': 'com.mataa.app',
      'appleAppId': '1234567890',
      'version': '5.4.1+3283',
      'auth': (auth ?? const ApiKeyUploadAuth('asc.prod')).toJson(),
    });

const _appleId = AppleIdUploadAuth(
  appleId: 'dev@example.com',
  passwordSecret: 'apple.password',
);

StreamingContext _context(
  String fixture, {
  int exitCode = 0,
  bool cancelled = false,
  String jobId = 'job_1',
}) => StreamingContext.single(
  altoolFixture(fixture),
  exit: ProcessExit(exitCode: exitCode, cancelled: cancelled),
  jobId: jobId,
);

void main() {
  late InMemoryArtifactRepository repository;
  late LocalInMemoryArtifactStore store;
  late MemorySecretStore secrets;
  late FakeAppStoreConnect connect;
  late AscKey? keyConnectedWith;
  late List<Duration> sleeps;

  UploadAppStoreStep step({
    bool isMacOS = true,
    Duration processingTimeout = const Duration(minutes: 2),
  }) => UploadAppStoreStep(
    repository: repository,
    store: store,
    secrets: secrets,
    connect: (key) {
      keyConnectedWith = key;
      return connect;
    },
    isMacOS: isMacOS,
    processingTimeout: processingTimeout,
    sleep: (duration) async => sleeps.add(duration),
  );

  Future<void> putIpa({String name = _ipaName, String jobId = 'job_1'}) async {
    final recorder = ArtifactRecorder(
      store: store,
      repository: repository,
      clock: ManualClock(DateTime.utc(2026, 10, 13)),
    );
    await recorder.record(
      jobId: jobId,
      kind: ArtifactKind.ipa,
      name: name,
      content: Stream.value(utf8.encode('ipa bytes')),
    );
  }

  setUp(() async {
    repository = InMemoryArtifactRepository();
    store = LocalInMemoryArtifactStore();
    secrets = MemorySecretStore()
      ..values['asc.prod'] = _key.toSecret()
      ..values['apple.password'] = _password;
    connect = FakeAppStoreConnect();
    keyConnectedWith = null;
    sleeps = [];
    await putIpa();
  });

  group('the step', () {
    test('is upload.appStore and has a side effect', () {
      expect(step().kind, 'upload.appStore');
      expect(step().sideEffectOf(_input()), isTrue);
    });

    test('stores its input and result as JSON', () {
      final input = _input();

      expect(step().decodeInput(step().encodeInput(input)), input);
      expect(step().encodeResult(const UploadAppStoreResult(confirmed: true)), {
        'alreadyUploaded': false,
        'confirmed': true,
      });
    });
  });

  group('upload with an API key', () {
    test('sends the IPA through the API, on any machine', () async {
      final context = StreamingContext.single(const []);

      final outcome = await step(isMacOS: false).run(_input(), context);

      expect(context.commands, isEmpty);
      expect(keyConnectedWith, _key);
      expect(connect.calls, [
        'uploadBuild 1234567890 5.4.1 3283 $_ipaName 9',
        'buildUpload upload-1',
      ]);
      expect(connect.uploads.values.single, utf8.encode('ipa bytes'));
      expect(
        outcome,
        isA<StepSucceeded<UploadAppStoreResult>>().having(
          (o) => o.result,
          'result',
          const UploadAppStoreResult(
            confirmed: true,
            buildId: 'build-of-upload-1',
          ),
        ),
      );
    });

    test('polls until App Store Connect made the build', () async {
      connect.uploadAnswers.addAll(const [
        AscBuildUpload(id: 'upload-1', state: AscBuildUploadState.processing),
        AscBuildUpload(
          id: 'upload-1',
          state: AscBuildUploadState.complete,
          buildId: 'build-9',
          warnings: [
            AscUploadIssue(
              code: '90683',
              description: 'A purpose string is missing.',
            ),
          ],
        ),
      ]);

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      expect(connect.calls.skip(1), [
        'buildUpload upload-1',
        'buildUpload upload-1',
      ]);
      expect(sleeps, const [Duration(seconds: 15), Duration(seconds: 15)]);
      expect(
        (outcome as StepSucceeded<UploadAppStoreResult>).result,
        const UploadAppStoreResult(
          confirmed: true,
          buildId: 'build-9',
          warnings: ['90683: A purpose string is missing.'],
        ),
      );
      expect(outcome.result.toJson()['warnings'], [
        '90683: A purpose string is missing.',
      ]);
    });

    test('reports a rejected build the way altool does', () async {
      connect.uploadAnswers.add(
        const AscBuildUpload(
          id: 'upload-1',
          state: AscBuildUploadState.failed,
          errors: [
            AscUploadIssue(
              code: 'STATE_ERROR.VALIDATION_ERROR',
              description: 'ITMS-90186: The train is closed.',
            ),
          ],
        ),
      );

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      final message = (outcome as StepFailed).message;
      expect(message, startsWith('App Store Connect rejected the build: '));
      expect(message, contains('ITMS-90186: The train is closed.'));
      expect(message, contains('Bump the version'));
      expect(message, endsWith('$_ipaName in the artifact store.'));
    });

    test('reports a rejection without errors', () async {
      connect.uploadAnswers.add(
        const AscBuildUpload(id: 'upload-1', state: AscBuildUploadState.failed),
      );

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      expect(
        (outcome as StepFailed).message,
        'App Store Connect rejected the build. The IPA is still $_ipaName in '
        'the artifact store.',
      );
    });

    test('gives up when processing takes too long', () async {
      connect.uploadAnswers.add(
        const AscBuildUpload(
          id: 'upload-1',
          state: AscBuildUploadState.processing,
        ),
      );

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      final message = (outcome as StepFailed).message;
      expect(
        message,
        startsWith(
          'App Store Connect did not accept or refuse the upload (upload-1) '
          'of build 3283 in 2 minutes.',
        ),
      );
      expect(message, contains('Resume the step later'));
      expect(sleeps, hasLength(8));
    });

    test('says a short wait in seconds', () async {
      connect.uploadAnswers.add(
        const AscBuildUpload(
          id: 'upload-1',
          state: AscBuildUploadState.processing,
        ),
      );

      final outcome = await step(processingTimeout: const Duration(seconds: 30))
          .run(_input(), StreamingContext.single(const []));

      expect((outcome as StepFailed).message, contains('in 30 seconds.'));
      expect(sleeps, hasLength(2));
    });

    test('stops polling when the job is cancelled', () async {
      connect.uploadAnswers.add(
        const AscBuildUpload(
          id: 'upload-1',
          state: AscBuildUploadState.processing,
        ),
      );
      final context = StreamingContext.single(const [])..isStopping = true;

      final outcome = await step().run(_input(), context);

      expect((outcome as StepFailed).message, contains('cancelled'));
      expect(sleeps, isEmpty);
    });

    test('reports a refusal with its cure', () async {
      connect.failure = const AscConflictException(
        'The bundle version must be higher (90189).',
        code: 'ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE',
      );

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      final message = (outcome as StepFailed).message;
      expect(
        message,
        startsWith(
          'App Store Connect refused the upload: The bundle version must be '
          'higher (90189).',
        ),
      );
      expect(message, contains('Allocate a new build number'));
    });

    test('reports a refusal without a known cure with its fix', () async {
      connect.failure = const AscForbiddenException('No role.');

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      expect((outcome as StepFailed).message, contains('App Manager'));
    });
  });

  group('a rejection by altool', () {
    StreamingContext altool(String fixture, {int exitCode = 0}) =>
        _context(fixture, exitCode: exitCode);

    test('that exited 0 fails the step (closed train)', () async {
      final outcome = await step().run(
        _input(auth: _appleId),
        altool('altool_closed_train_exit0.txt'),
      );

      expect(outcome, isA<StepFailed>());
      final message = (outcome as StepFailed).message;
      expect(message, contains('altool exited 0 but reported errors'));
      expect(message, contains('ERROR ITMS-90186'));
      expect(message, contains('Bump the version'));
      expect(message, contains('step log'));
      expect(message, contains(_ipaName));
    });

    test('with a non-zero exit fails the step with the code', () async {
      final outcome = await step().run(
        _input(auth: _appleId),
        altool('altool_redundant_binary.txt', exitCode: 1),
      );

      final message = (outcome as StepFailed).message;
      expect(message, startsWith('altool exited with code 1: '));
      expect(message, contains('Allocate a new build number'));
    });

    test('with a non-zero exit and no error line says so', () async {
      final outcome = await step().run(
        _input(auth: _appleId),
        StreamingContext.single([
          'something odd',
        ], exit: const ProcessExit(exitCode: 2)),
      );

      expect(
        (outcome as StepFailed).message,
        startsWith('altool exited with code 2. The step log'),
      );
    });

    test('that was cancelled fails the step', () async {
      final outcome = await step().run(
        _input(auth: _appleId),
        _context('altool_upload_succeeded.txt', exitCode: -15, cancelled: true),
      );

      expect((outcome as StepFailed).message, contains('cancelled'));
    });

    test('fails when xcrun cannot be started', () async {
      final context = StreamingContext(
        (_, _) => throw const ProcessStartException('xcrun', 'not found'),
      );

      final outcome = await step().run(_input(auth: _appleId), context);

      expect((outcome as StepFailed).message, contains('xcode-select'));
    });
  });

  group('before the upload', () {
    test('fails off macOS for an Apple ID', () async {
      final context = StreamingContext.single(const []);

      final outcome = await step(isMacOS: false)
          .run(_input(auth: _appleId), context);

      final message = (outcome as StepFailed).message;
      expect(message, contains('needs macOS'));
      expect(message, contains('App Store Connect API key'));
      expect(context.commands, isEmpty);
    });

    test('fails without an IPA of that name in the job', () async {
      final context = StreamingContext.single(const [], jobId: 'job_2');

      final outcome = await step().run(_input(), context);

      expect((outcome as StepFailed).message, contains('no intact IPA'));
      expect(connect.calls, isEmpty);
    });

    test('finds the IPA in the build job the input names', () async {
      await putIpa(jobId: 'job_build');
      store.files.remove('job_1/$_ipaName');
      final context = _context('altool_upload_succeeded.txt', jobId: 'job_2');

      final outcome = await step().run(
        UploadAppStoreInput.fromJson({
          ..._input(auth: _appleId).toJson(),
          'artifactJob': 'job_build',
        }),
        context,
      );

      expect(outcome, isA<StepSucceeded<UploadAppStoreResult>>());
      expect(
        context.commands.single.arguments,
        contains('/artifacts/job_build/$_ipaName'),
      );
    });

    test('says which job lacks the IPA when it is another one', () async {
      final context = StreamingContext.single(const []);

      final outcome = await step().run(
        UploadAppStoreInput.fromJson({
          ..._input().toJson(),
          'artifactJob': 'job_other',
        }),
        context,
      );

      expect(
        (outcome as StepFailed).message,
        contains('The build job job_other has no intact IPA'),
      );
      expect(connect.calls, isEmpty);
    });

    test('fails when the stored IPA changed', () async {
      store.files['job_1/$_ipaName'] = utf8.encode('other bytes');
      final context = StreamingContext.single(const []);

      final outcome = await step().run(_input(), context);

      expect((outcome as StepFailed).message, contains('no intact IPA'));
      expect(connect.calls, isEmpty);
    });

    test('fails when the ASC key secret is missing', () async {
      secrets.values.remove('asc.prod');

      final outcome = await step().run(
        _input(),
        StreamingContext.single(const []),
      );

      expect(
        (outcome as StepFailed).message,
        'There is no ASC key under "asc.prod" in the secret store.',
      );
    });

    test(
      'fails when the ASC key secret is malformed, without the secret',
      () async {
        secrets.values['asc.prod'] = '{"keyId": "K"}';

        final outcome = await step().run(
          _input(),
          StreamingContext.single(const []),
        );

        expect(
          (outcome as StepFailed).message,
          contains('not a usable ASC key'),
        );
        expect(connect.calls, isEmpty);
      },
    );
  });

  group('upload with an Apple ID', () {
    test('passes the app-specific password as @env, never in argv', () async {
      final context = _context('altool_upload_succeeded.txt');

      final outcome = await step().run(_input(auth: _appleId), context);

      final command = context.commands.single;
      expect(command.arguments, [
        'altool',
        '--upload-package',
        '/artifacts/job_1/$_ipaName',
        '--type',
        'ios',
        '--apple-id',
        '1234567890',
        '--bundle-id',
        'com.mataa.app',
        '--bundle-version',
        '3283',
        '--bundle-short-version-string',
        '5.4.1',
        '-u',
        'dev@example.com',
        '-p',
        '@env:XPATH_ASC_APP_PASSWORD',
      ]);
      expect(command.secretEnvironment, {
        'XPATH_ASC_APP_PASSWORD': 'apple.password',
      });
      expect(command.environment, isEmpty);
      expect(command.arguments.join(' '), isNot(contains(_password)));
      expect(outcome, isA<StepSucceeded<UploadAppStoreResult>>());
    });

    test('fails on a rejection that exited 0', () async {
      final outcome = await step().run(
        _input(auth: _appleId),
        _context('altool_closed_train_exit0.txt'),
      );

      expect((outcome as StepFailed).message, contains('exited 0'));
    });
  });

  group('alreadyDone with an API key', () {
    setUp(() {
      connect.buildsOf['1234567890'] = const [
        AscBuild(
          id: 'build-1',
          buildNumber: '3283',
          version: '5.4.1',
          processingState: AscProcessingState.processing,
        ),
      ];
    });

    test('is the build App Store Connect has', () async {
      final result = await step().alreadyDone(
        _input(),
        StreamingContext.single(const []),
      );

      expect(
        result,
        const UploadAppStoreResult(
          alreadyUploaded: true,
          confirmed: true,
          buildId: 'build-1',
          processingState: 'PROCESSING',
        ),
      );
      expect(connect.calls, ['builds 1234567890 5.4.1 3283']);
      expect(keyConnectedWith, _key);
    });

    test('is null when the build is not there', () async {
      connect.buildsOf.clear();

      expect(
        await step().alreadyDone(_input(), StreamingContext.single(const [])),
        isNull,
      );
    });

    test('is null when App Store Connect cannot be asked', () async {
      connect.failure = const AscAuthException('no');

      expect(
        await step().alreadyDone(_input(), StreamingContext.single(const [])),
        isNull,
      );
    });

    test('is null when the key is missing or malformed', () async {
      secrets.values.remove('asc.prod');
      expect(
        await step().alreadyDone(_input(), StreamingContext.single(const [])),
        isNull,
      );

      secrets.values['asc.prod'] = 'nope';
      expect(
        await step().alreadyDone(_input(), StreamingContext.single(const [])),
        isNull,
      );
      expect(connect.calls, isEmpty);
    });
  });

  group('alreadyDone with an Apple ID', () {
    Future<UploadAppStoreResult?> ask(
      StreamingContext context, {
      bool isMacOS = true,
    }) => step(isMacOS: isMacOS).alreadyDone(_input(auth: _appleId), context);

    test(
      'asks altool --build-status and is done when it names the build',
      () async {
        final context = StreamingContext.single([
          'Build 3283 of 5.4.1: state PROCESSING',
        ]);

        final result = await ask(context);

        expect(
          result,
          const UploadAppStoreResult(alreadyUploaded: true, confirmed: true),
        );
        final command = context.commands.single;
        expect(command.arguments, [
          'altool',
          '--build-status',
          '--apple-id',
          '1234567890',
          '--bundle-version',
          '3283',
          '--bundle-short-version-string',
          '5.4.1',
          '--platform',
          'ios',
          '-u',
          'dev@example.com',
          '-p',
          '@env:XPATH_ASC_APP_PASSWORD',
        ]);
        expect(command.secretEnvironment, {
          'XPATH_ASC_APP_PASSWORD': 'apple.password',
        });
      },
    );

    test(
      'is not done when altool fails, errs, or does not name the build',
      () async {
        expect(
          await ask(
            StreamingContext.single([
              'Build 3283',
            ], exit: const ProcessExit(exitCode: 1)),
          ),
          isNull,
        );
        expect(
          await ask(StreamingContext.single(['ERROR: Build 3283 not found'])),
          isNull,
        );
        expect(
          await ask(StreamingContext.single(['Build 32831 is ready'])),
          isNull,
        );
        expect(await ask(StreamingContext.single(const [])), isNull);
      },
    );

    test('is not done off macOS or when xcrun is missing', () async {
      final context = StreamingContext.single(['Build 3283']);

      expect(await ask(context, isMacOS: false), isNull);
      expect(context.commands, isEmpty);
      expect(
        await ask(
          StreamingContext(
            (_, _) => throw const ProcessStartException('xcrun', 'gone'),
          ),
        ),
        isNull,
      );
    });
  });
}
