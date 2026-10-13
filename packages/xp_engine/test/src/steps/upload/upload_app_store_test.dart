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
  late InMemorySecretFileStore secretFiles;
  late FakeAppStoreConnect connect;
  late AscKey? keyConnectedWith;

  UploadAppStoreStep step({bool isMacOS = true}) => UploadAppStoreStep(
    repository: repository,
    store: store,
    secrets: secrets,
    secretFiles: secretFiles,
    connect: (key) {
      keyConnectedWith = key;
      return connect;
    },
    isMacOS: isMacOS,
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
    secretFiles = InMemorySecretFileStore();
    connect = FakeAppStoreConnect();
    keyConnectedWith = null;
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
    test(
      'runs altool with the key from this job and no secret in argv',
      () async {
        final context = _context('altool_upload_succeeded.txt');

        final outcome = await step().run(_input(), context);

        final command = context.commands.single;
        expect(command.executable, 'xcrun');
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
          '--apiKey',
          'ABC123DEF4',
          '--apiIssuer',
          '57246542-96fe-1a63-e053-0824d011072a',
        ]);
        expect(command.environment, {'API_PRIVATE_KEYS_DIR': '/secrets/job_1'});
        expect(command.passThroughEnvironment, ['DEVELOPER_DIR']);
        expect(command.secretEnvironment, isEmpty);
        expect(secretFiles.files, {
          '/secrets/job_1/AuthKey_ABC123DEF4.p8': _key.privateKey,
        });
        expect(command.arguments.join(' '), isNot(contains('PRIVATE KEY')));
        expect(
          outcome,
          isA<StepSucceeded<UploadAppStoreResult>>().having(
            (o) => o.result,
            'result',
            const UploadAppStoreResult(
              confirmed: true,
              deliveryId: '3d6a9d4a-8f0e-4a62-9d8b-1c2f5b7e9a10',
            ),
          ),
        );
      },
    );

    test(
      'names an individual key ApiKey_ so that altool signs sub: user',
      () async {
        secrets.values['asc.prod'] = const AscKey(
          keyId: 'IND1234567',
          issuerId: 'issuer',
          privateKey: 'pem',
          kind: AscKeyKind.individual,
        ).toSecret();

        await step().run(_input(), _context('altool_upload_succeeded.txt'));

        expect(secretFiles.files.keys, ['/secrets/job_1/ApiKey_IND1234567.p8']);
      },
    );

    test(
      'succeeds, unconfirmed, when altool prints nothing wrong or right',
      () async {
        final context = StreamingContext.single(['Uploading']);

        final outcome = await step().run(_input(), context);

        expect(
          (outcome as StepSucceeded<UploadAppStoreResult>).result,
          const UploadAppStoreResult(),
        );
      },
    );
  });

  group('a rejection', () {
    test('that exited 0 fails the step (closed train)', () async {
      final outcome = await step().run(
        _input(),
        _context('altool_closed_train_exit0.txt'),
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
        _input(),
        _context('altool_redundant_binary.txt', exitCode: 1),
      );

      final message = (outcome as StepFailed).message;
      expect(message, startsWith('altool exited with code 1: '));
      expect(message, contains('Allocate a new build number'));
    });

    test('with a non-zero exit and no error line says so', () async {
      final outcome = await step().run(
        _input(),
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
        _input(),
        _context('altool_upload_succeeded.txt', exitCode: -15, cancelled: true),
      );

      expect((outcome as StepFailed).message, contains('cancelled'));
    });

    test('fails when xcrun cannot be started', () async {
      final context = StreamingContext(
        (_, _) => throw const ProcessStartException('xcrun', 'not found'),
      );

      final outcome = await step().run(_input(), context);

      expect((outcome as StepFailed).message, contains('xcode-select'));
    });
  });

  group('before the upload', () {
    test('fails off macOS', () async {
      final context = StreamingContext.single(const []);

      final outcome = await step(isMacOS: false).run(_input(), context);

      expect((outcome as StepFailed).message, contains('needs macOS'));
      expect(context.commands, isEmpty);
    });

    test('fails without an IPA of that name in the job', () async {
      final context = StreamingContext.single(const [], jobId: 'job_2');

      final outcome = await step().run(_input(), context);

      expect((outcome as StepFailed).message, contains('no intact IPA'));
      expect(context.commands, isEmpty);
    });

    test('fails when the stored IPA changed', () async {
      store.files['job_1/$_ipaName'] = utf8.encode('other bytes');
      final context = StreamingContext.single(const []);

      final outcome = await step().run(_input(), context);

      expect((outcome as StepFailed).message, contains('no intact IPA'));
      expect(context.commands, isEmpty);
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
        expect(secretFiles.written, isEmpty);
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
      expect(secretFiles.written, isEmpty);
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
