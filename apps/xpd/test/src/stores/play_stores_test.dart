import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_play/xp_fake_play.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/job_fakes.dart';

const _package = 'com.mataa.app';

void main() {
  late ManualClock clock;
  late SqliteDatabase database;
  late MemorySecretStore secrets;
  late FakePlayServer server;
  late PlayStores play;

  void addFlavor(String id, String androidAppId, {String? credentialKind}) {
    database.connection.execute(
      'INSERT INTO flavor (id, app_id, name, entrypoint, android_app_id) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, 'app_1', id, 'lib/main.dart', androidAppId],
    );
    if (credentialKind != null) {
      database.connection
        ..execute(
          'INSERT INTO credential (id, name, kind, secret_key) '
          'VALUES (?, ?, ?, ?)',
          ['cred_$id', 'cred_$id', credentialKind, 'play.$id'],
        )
        ..execute(
          'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
          'VALUES (?, ?, ?)',
          [id, credentialKind, 'cred_$id'],
        );
    }
  }

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_1', 'github.com', '1', 1, "
        "'https://github.com/a/b.git', 'main')",
      )
      ..execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('app_1', 'prj_1', '.', 'flutter', 'sa')",
      );
    secrets = MemorySecretStore();
    server = await FakePlayServer.start(now: clock.now);
    addTearDown(server.close);
    play = PlayStores(
      database: database,
      secrets: secrets,
      clock: clock,
      apiBaseUrl: server.baseUrl,
      uploadBaseUrl: server.baseUrl,
    );
    addTearDown(play.close);
  });

  group('a flavor with a play_sa credential', () {
    setUp(() {
      addFlavor('prod', _package, credentialKind: 'play_sa');
      secrets.values['play.prod'] = server.serviceAccountJson();
      server.addApp(_package)
        ..addRelease('production', [3282])
        ..addRelease('internal', [3283]);
    });

    test('knows the version codes Play has seen', () async {
      final builds = await play.buildNumbers.lookup(
        iosBundleId: 'com.mataa.ios',
        androidAppId: _package,
      );

      expect(builds, const StoreBuilds({3282, 3283}));
      expect(server.requests.where((r) => r.tokenProblem != null), isEmpty);
    });

    test('keeps one client, and its token, per account', () async {
      final account = (await play.credentials.forAndroidAppId(_package))!;

      expect(play.connect(account), same(play.connect(account)));
    });

    test('uploads a bundle end to end through the step', () async {
      server.apps[_package]!.tracks.clear();
      final repository = InMemoryArtifactRepository();
      final store = InMemoryArtifactStore();
      await ArtifactRecorder(
        store: store,
        repository: repository,
        clock: clock,
      ).record(
        jobId: 'job_1',
        kind: ArtifactKind.aab,
        name: 'prod.aab',
        content: Stream.value(fakeAab(3284, padding: 64)),
      );
      final step = play.uploadStep(
        repository: repository,
        store: store,
        secrets: secrets,
      );

      final input = <String, dynamic>{
        'artifactName': 'prod.aab',
        'packageName': _package,
        'version': '5.4.1+3284',
        'serviceAccountSecret': 'play.prod',
      };

      final outcome = await step.run(
        UploadPlayInput.fromJson(input),
        _Context(),
      );

      expect(step.kind, 'upload.play');
      expect(
        (outcome as StepSucceeded<UploadPlayResult>).result,
        const UploadPlayResult(
          versionCode: 3284,
          track: 'internal',
          lifecycleState: PlayLifecycleState.published,
        ),
      );
      expect(
        server.commits.single.changesInReviewBehavior,
        'ERROR_IF_IN_REVIEW',
      );
    });
  });

  group('a flavor without a service account', () {
    setUp(() => addFlavor('prod', _package));

    test('cannot tell the version codes', () async {
      expect(await play.buildNumbers.lookup(androidAppId: _package), isNull);
      expect(server.requests, isEmpty);
    });
  });

  group('the target API level', () {
    test('is the default, and is read from the environment', () async {
      expect(await play.requirements.requiredTargetSdk(), defaultPlayTargetSdk);
      expect(PlayStores.targetSdkFrom(null), defaultPlayTargetSdk);
      expect(PlayStores.targetSdkFrom(' 37 '), 37);
    });

    test('can be set', () async {
      final custom = PlayStores(
        database: database,
        secrets: secrets,
        clock: clock,
        requiredTargetSdk: 37,
      );
      addTearDown(custom.close);

      expect(await custom.requirements.requiredTargetSdk(), 37);
    });

    test('is refused when it is not an API level', () {
      for (final bad in ['latest', '', '20', '100', '36.5']) {
        expect(
          () => PlayStores.targetSdkFrom(bad),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('XPD_PLAY_TARGET_SDK must be an API level'),
            ),
          ),
          reason: bad,
        );
      }
    });
  });

  test('wires the playTargetSdk check', () {
    expect(play.guardChecks.map((check) => check.name), [
      GuardCheckName.playTargetSdk,
    ]);
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
