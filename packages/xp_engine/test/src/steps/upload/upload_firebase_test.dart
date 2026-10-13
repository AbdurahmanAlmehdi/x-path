import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/job_harness.dart';
import '../../../helpers/local_artifact_store.dart';
import '../../../helpers/step_context.dart';

const _apkName = 'dev-1.2.3+45.apk';
const _appId = '1:684690133351:android:b434734f585770367c1fc2';
const _app = 'projects/684690133351/apps/$_appId';
const _account = PlayServiceAccount(
  clientEmail: 'xpath@project.iam.gserviceaccount.com',
  privateKey: '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n',
);

UploadFirebaseInput _input({Map<String, dynamic> overrides = const {}}) =>
    UploadFirebaseInput.fromJson({
      'artifactName': _apkName,
      'appId': _appId,
      'version': '1.2.3+45',
      'serviceAccountSecret': 'firebase.dev',
      ...overrides,
    });

FirebaseRelease _release({
  String id = 'rel-9',
  String? displayVersion = '1.2.3',
  String? buildVersion = '45',
  String? notes,
}) => FirebaseRelease(
  name: '$_app/releases/$id',
  displayVersion: displayVersion,
  buildVersion: buildVersion,
  releaseNotes: notes,
  firebaseConsoleUri: 'https://console.firebase.google.com/r',
  testingUri: 'https://appdistribution.firebase.google.com/t',
);

class _StoppingContext extends NoProcessContext {
  @override
  bool get isStopping => true;
}

void main() {
  late InMemoryArtifactRepository repository;
  late LocalInMemoryArtifactStore store;
  late MemorySecretStore secrets;
  late FakeFirebaseAppDistribution firebase;
  late PlayServiceAccount? connectedWith;
  late List<Duration> slept;

  UploadFirebaseStep step({int maxPolls = 5}) => UploadFirebaseStep(
    repository: repository,
    store: store,
    secrets: secrets,
    maxPolls: maxPolls,
    pollInterval: const Duration(seconds: 2),
    sleep: (duration) async => slept.add(duration),
    connect: (account) {
      connectedWith = account;
      return firebase;
    },
  );

  Future<void> putBinary({
    String name = _apkName,
    ArtifactKind kind = ArtifactKind.apk,
  }) async {
    await ArtifactRecorder(
      store: store,
      repository: repository,
      clock: ManualClock(DateTime.utc(2026, 10, 13)),
    ).record(
      jobId: 'job_1',
      kind: kind,
      name: name,
      content: Stream.value(utf8.encode('apk bytes')),
    );
  }

  Future<StepOutcome<UploadFirebaseResult>> run([
    UploadFirebaseInput? input,
    StepContext? context,
  ]) => step().run(input ?? _input(), context ?? NoProcessContext());

  String message(StepOutcome<UploadFirebaseResult> outcome) =>
      (outcome as StepFailed).message;

  FirebaseOperation done({
    FirebaseRelease? release,
    FirebaseUploadResult result = FirebaseUploadResult.created,
    String? error,
  }) => FirebaseOperation(
    name: '$_app/releases/-/operations/op1',
    done: true,
    release: release,
    result: result,
    error: error,
  );

  setUp(() async {
    repository = InMemoryArtifactRepository();
    store = LocalInMemoryArtifactStore();
    secrets = MemorySecretStore()..values['firebase.dev'] = _account.toSecret();
    firebase = FakeFirebaseAppDistribution()
      ..uploadOperations.add(done(release: _release()));
    connectedWith = null;
    slept = [];
    await putBinary();
  });

  group('the step', () {
    test('is upload.firebase and has a side effect', () {
      expect(step().kind, 'upload.firebase');
      expect(step().sideEffectOf(_input()), isTrue);
    });

    test('stores its input and result as JSON', () {
      final input = _input(overrides: {'releaseNotes': 'Fixes'});

      expect(step().decodeInput(step().encodeInput(input)), input);
      expect(
        step().encodeResult(const UploadFirebaseResult(releaseName: 'r')),
        {'releaseName': 'r', 'alreadyUploaded': false, 'distributed': false},
      );
    });
  });

  group('the upload', () {
    test('streams the binary and returns the release', () async {
      final outcome = await run();

      expect(connectedWith, _account);
      expect(firebase.calls, ['uploadRelease $_app 9 $_apkName']);
      expect(utf8.decode(firebase.uploads.single), 'apk bytes');
      expect(
        (outcome as StepSucceeded<UploadFirebaseResult>).result,
        const UploadFirebaseResult(
          releaseName: '$_app/releases/rel-9',
          displayVersion: '1.2.3',
          buildVersion: '45',
          result: FirebaseUploadResult.created,
          consoleUri: 'https://console.firebase.google.com/r',
          testingUri: 'https://appdistribution.firebase.google.com/t',
        ),
      );
      expect(slept, isEmpty);
    });

    test('sets the notes, then distributes to testers and groups', () async {
      final outcome = await run(
        _input(
          overrides: {
            'releaseNotes': 'Fixes',
            'testerEmails': ['a@example.com'],
            'groupAliases': ['qa'],
          },
        ),
      );

      expect(firebase.calls, [
        'uploadRelease $_app 9 $_apkName',
        'updateReleaseNotes $_app/releases/rel-9',
        'distribute $_app/releases/rel-9',
      ]);
      expect(firebase.notes, ['$_app/releases/rel-9 Fixes']);
      expect(firebase.distributions, [
        '$_app/releases/rel-9 testers=a@example.com groups=qa',
      ]);
      expect(
        (outcome as StepSucceeded<UploadFirebaseResult>).result.distributed,
        isTrue,
      );
    });

    test('skips empty notes and distributes to nobody', () async {
      await run(_input(overrides: {'releaseNotes': ''}));

      expect(firebase.notes, isEmpty);
      expect(firebase.distributions, isEmpty);
    });

    test('uploads an AAB and an IPA by their kind', () async {
      await putBinary(name: 'dev-1.2.3+45.aab', kind: ArtifactKind.aab);
      await putBinary(name: 'dev-1.2.3+45.ipa', kind: ArtifactKind.ipa);
      firebase.uploadOperations.addAll([
        done(release: _release()),
        done(release: _release()),
      ]);

      expect(
        await run(_input(overrides: {'artifactName': 'dev-1.2.3+45.aab'})),
        isA<StepSucceeded<UploadFirebaseResult>>(),
      );
      expect(
        await run(_input(overrides: {'artifactName': 'dev-1.2.3+45.ipa'})),
        isA<StepSucceeded<UploadFirebaseResult>>(),
      );
    });

    test('polls the operation until it is done', () async {
      firebase.uploadOperations
        ..clear()
        ..add(const FirebaseOperation(name: '$_app/releases/-/operations/op1'));
      firebase.operationsOf['$_app/releases/-/operations/op1'] = [
        const FirebaseOperation(name: '$_app/releases/-/operations/op1'),
        done(release: _release(), result: FirebaseUploadResult.updated),
      ];

      final outcome = await run();

      expect(slept, [const Duration(seconds: 2), const Duration(seconds: 2)]);
      expect(
        (outcome as StepSucceeded<UploadFirebaseResult>).result.result,
        FirebaseUploadResult.updated,
      );
    });

    test('gives up after the polls it allows and says how to go on', () async {
      firebase.uploadOperations
        ..clear()
        ..add(const FirebaseOperation(name: '$_app/releases/-/operations/op1'));

      final outcome = await step(maxPolls: 2).run(_input(), NoProcessContext());

      expect(message(outcome), contains('still processing'));
      expect(message(outcome), contains('after 4 seconds'));
      expect(slept, hasLength(2));
    });

    test('stops polling when the job is stopping', () async {
      firebase.uploadOperations
        ..clear()
        ..add(const FirebaseOperation(name: '$_app/releases/-/operations/op1'));

      final outcome = await run(_input(), _StoppingContext());

      expect(message(outcome), contains('cancelled'));
      expect(slept, isEmpty);
    });
  });

  group('failures', () {
    test('fails without an intact binary', () async {
      store.files.remove('job_1/$_apkName');

      expect(
        message(await run()),
        allOf(contains('no intact APK'), contains(_apkName)),
      );
      expect(firebase.calls, isEmpty);
    });

    test('fails without a service account', () async {
      secrets.values.clear();

      expect(message(await run()), contains('There is no service account'));
    });

    test('fails with an unusable service account', () async {
      secrets.values['firebase.dev'] = 'not json';

      expect(message(await run()), contains('not a usable service account'));
    });

    test('says what Firebase refused, with the fix', () async {
      firebase.failures['uploadRelease'] = const FirebaseForbiddenException(
        'The caller does not have permission',
      );

      final text = message(await run());

      expect(text, contains('The caller does not have permission'));
      expect(text, contains('Firebase App Distribution Admin'));
      expect(text, isNot(contains('is in Firebase already')));
    });

    test('fails when Firebase could not process the binary', () async {
      firebase.uploadOperations
        ..clear()
        ..add(done(error: 'Invalid APK'));

      expect(message(await run()), contains('Invalid APK'));
    });

    test('fails when the finished upload names no release', () async {
      firebase.uploadOperations
        ..clear()
        ..add(done());

      expect(message(await run()), contains('named no release'));
    });

    test('fails when the binary carries another version', () async {
      firebase.uploadOperations
        ..clear()
        ..add(done(release: _release(buildVersion: '44')));

      final text = message(await run());

      expect(text, contains('read version 1.2.3 (44)'));
      expect(text, contains('not 1.2.3+45'));
      expect(firebase.notes, isEmpty);
    });

    test('fails when the version name differs', () async {
      firebase.uploadOperations
        ..clear()
        ..add(done(release: _release(displayVersion: '1.2.2')));

      expect(message(await run()), contains('read version 1.2.2 (45)'));
    });

    test('accepts a release that reports no versions', () async {
      firebase.uploadOperations
        ..clear()
        ..add(
          done(release: _release(displayVersion: null, buildVersion: null)),
        );

      expect(await run(), isA<StepSucceeded<UploadFirebaseResult>>());
    });

    test('tells how to finish when the notes fail after the upload', () async {
      firebase.failures['updateReleaseNotes'] = const FirebaseServerException(
        503,
        'Backend error',
      );

      final text = message(await run(_input(overrides: {'releaseNotes': 'x'})));

      expect(text, contains('Backend error'));
      expect(text, contains('is in Firebase already'));
      expect(text, contains('$_app/releases/rel-9'));
    });

    test('tells how to finish when the distribution fails', () async {
      firebase.failures['distribute'] = const FirebaseValidationException(
        400,
        'Group qa does not exist',
      );

      final text = message(
        await run(
          _input(
            overrides: {
              'groupAliases': ['qa'],
            },
          ),
        ),
      );

      expect(text, contains('Group qa does not exist'));
      expect(text, contains('distribution'));
    });
  });

  group('alreadyDone', () {
    test('is done when a release has the build and the version name', () async {
      firebase.releasesOf[_app] = [
        _release(id: 'other', buildVersion: '44'),
        _release(),
      ];

      final done = await step().alreadyDone(_input(), NoProcessContext());

      expect(
        done,
        const UploadFirebaseResult(
          releaseName: '$_app/releases/rel-9',
          displayVersion: '1.2.3',
          buildVersion: '45',
          alreadyUploaded: true,
          consoleUri: 'https://console.firebase.google.com/r',
          testingUri: 'https://appdistribution.firebase.google.com/t',
        ),
      );
      expect(firebase.calls, ['releases $_app 3']);
      expect(connectedWith, _account);
    });

    test('is not done without such a release', () async {
      firebase.releasesOf[_app] = [_release(buildVersion: '44')];

      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);

      firebase.releasesOf[_app] = [_release(displayVersion: '1.2.2')];

      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);
    });

    test('is done when the notes match, not when they differ', () async {
      final input = _input(overrides: {'releaseNotes': 'Fixes'});
      firebase.releasesOf[_app] = [_release(notes: 'Fixes')];

      expect(await step().alreadyDone(input, NoProcessContext()), isNotNull);

      firebase.releasesOf[_app] = [_release(notes: 'Old')];

      expect(await step().alreadyDone(input, NoProcessContext()), isNull);

      firebase.releasesOf[_app] = [_release()];

      expect(await step().alreadyDone(input, NoProcessContext()), isNull);
    });

    test('cannot tell when the account or Firebase is out of reach', () async {
      firebase.releasesOf[_app] = [_release()];
      firebase.failures['releases'] = const FirebaseServerException(503, 'x');

      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);

      secrets.values['firebase.dev'] = 'not json';
      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);

      secrets.values.clear();
      expect(await step().alreadyDone(_input(), NoProcessContext()), isNull);
    });
  });
}
