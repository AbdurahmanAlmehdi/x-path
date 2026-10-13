import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/job_fakes.dart';

const _appId = '1:684690133351:android:b434734f585770367c1fc2';

void main() {
  late ManualClock clock;
  late MemorySecretStore secrets;
  late FakeFirebaseServer server;
  late FirebaseStores firebase;

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    secrets = MemorySecretStore();
    server = await FakeFirebaseServer.start(now: clock.now, pollsBeforeDone: 0);
    addTearDown(server.close);
    firebase = FirebaseStores(clock: clock, baseUrl: server.baseUrl);
    addTearDown(firebase.close);
    secrets.values['firebase.dev'] = server.serviceAccountJson();
  });

  test('keeps one client, and its token, per account', () {
    final account = PlayServiceAccount.fromSecret(server.serviceAccountJson());

    expect(firebase.connect(account), same(firebase.connect(account)));
    expect(firebase.connect(account), isA<HttpFirebaseAppDistribution>());
  });

  test('uploads an APK end to end through the step', () async {
    final app = server.addApp('684690133351', _appId, groups: {'qa'});
    final repository = InMemoryArtifactRepository();
    final store = InMemoryArtifactStore();
    await ArtifactRecorder(
      store: store,
      repository: repository,
      clock: clock,
    ).record(
      jobId: 'job_1',
      kind: ArtifactKind.apk,
      name: 'dev-1.2.3+45.apk',
      content: Stream.value(
        fakeBinary('apk', versionName: '1.2.3', versionCode: 45, padding: 64),
      ),
    );
    final step = firebase.uploadStep(
      repository: repository,
      store: store,
      secrets: secrets,
    );
    final input = UploadFirebaseInput.fromJson(const {
      'artifactName': 'dev-1.2.3+45.apk',
      'appId': _appId,
      'version': '1.2.3+45',
      'serviceAccountSecret': 'firebase.dev',
      'releaseNotes': 'Fixes',
      'groupAliases': ['qa'],
      'testerEmails': ['tester@example.com'],
    });

    final outcome = await step.run(input, _Context());

    expect(step.kind, 'upload.firebase');
    final result = (outcome as StepSucceeded<UploadFirebaseResult>).result;
    expect(result.displayVersion, '1.2.3');
    expect(result.buildVersion, '45');
    expect(result.result, FirebaseUploadResult.created);
    expect(result.distributed, isTrue);
    final release = app.releases.single;
    expect(release.notes, 'Fixes');
    expect(release.distributions, ['testers=tester@example.com groups=qa']);
    expect(server.requests.where((r) => r.tokenProblem != null), isEmpty);

    // A second run of the job finds the release and does not upload again.
    final again = await step.alreadyDone(input, _Context());
    expect(again?.alreadyUploaded, isTrue);
    expect(again?.releaseName, release.name);
  });
}

class _Context implements StepContext {
  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) => throw StateError('no process');
}
