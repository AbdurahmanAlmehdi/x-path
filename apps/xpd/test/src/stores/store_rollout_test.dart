import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';
import 'package:xp_fake_play/xp_fake_play.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/job_fakes.dart';

const _bundleId = 'com.mataa.app';
const _package = 'com.mataa.app';

/// The rollout step (U7a) through the store adapters the engine serves with,
/// against the fake App Store Connect and Google Play.
void main() {
  late SqliteDatabase database;
  late MemorySecretStore secrets;
  late FakeAscServer asc;
  late FakePlayServer playServer;
  late AppleStores apple;
  late PlayStores play;
  late InMemoryReleaseRepository releases;
  late StoreRolloutStep step;

  void assign(String kind, String secretKey) => database.connection
    ..execute(
      'INSERT INTO credential (id, name, kind, secret_key) VALUES (?, ?, ?, ?)',
      ['cred_$kind', 'cred_$kind', kind, secretKey],
    )
    ..execute(
      'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
      'VALUES (?, ?, ?)',
      ['prod', kind, 'cred_$kind'],
    );

  setUp(() async {
    final clock = ManualClock(DateTime.utc(2026, 10, 26, 12));
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
      )
      ..execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id, '
        'android_app_id) VALUES (?, ?, ?, ?, ?, ?)',
        ['prod', 'app_1', 'prod', 'lib/main.dart', _bundleId, _package],
      );
    assign('asc_key', 'asc.prod');
    assign('play_sa', 'play.prod');
    secrets = MemorySecretStore();
    asc = await FakeAscServer.start(now: clock.now);
    addTearDown(asc.close);
    playServer = await FakePlayServer.start(now: clock.now);
    addTearDown(playServer.close);
    secrets.values['asc.prod'] = const AscKey(
      keyId: fakeAscKeyId,
      issuerId: fakeAscIssuerId,
      privateKey: fakeAscPrivateKeyPem,
    ).toSecret();
    secrets.values['play.prod'] = playServer.serviceAccountJson();
    apple = AppleStores(
      database: database,
      secrets: secrets,
      clock: clock,
      ascBaseUrl: asc.baseUrl,
      itunesBaseUrl: asc.baseUrl,
    );
    addTearDown(apple.close);
    play = PlayStores(
      database: database,
      secrets: secrets,
      clock: clock,
      apiBaseUrl: playServer.baseUrl,
      uploadBaseUrl: playServer.baseUrl,
    );
    addTearDown(play.close);
    releases = InMemoryReleaseRepository();
    await releases.create(
      ReleaseRecord(
        id: 'rel_1',
        projectId: 'prj_1',
        appPath: '.',
        flavor: 'prod',
        version: '5.4.1',
        build: 3284,
        state: ReleaseState.live,
        stores: const {
          ReleaseStore.apple: StoreEntry(
            store: ReleaseStore.apple,
            state: StoreState.live,
            source: StatusSource.api,
            identity: {'bundleId': _bundleId, 'country': 'sa'},
          ),
          ReleaseStore.play: StoreEntry(
            store: ReleaseStore.play,
            state: StoreState.live,
            source: StatusSource.api,
            identity: {'packageName': _package, 'track': 'production'},
          ),
        },
        builds: const [],
        baseBranch: 'main',
        createdAt: DateTime.utc(2026, 10, 20),
        updatedAt: DateTime.utc(2026, 10, 20),
      ),
    );
    step = StoreRolloutStep(
      releases: releases,
      ascCredentials: apple.credentials,
      appStoreConnect: apple.connect,
      playCredentials: play.credentials,
      googlePlay: play.connect,
    );
  });

  Future<StoreRolloutResult> roll(RolloutRequest request) async {
    final outcome = await step.run(
      StoreRolloutInput(releaseId: 'rel_1', request: request),
      _Context(),
    );
    return (outcome as StepSucceeded<StoreRolloutResult>).result;
  }

  test("pauses Apple's phased release", () async {
    final app = asc.addApp(_bundleId);
    final version = asc.addVersion(
      app.id,
      '5.4.1',
      appVersionState: 'READY_FOR_DISTRIBUTION',
    );
    final phased = asc.addPhasedRelease(version.id, state: 'ACTIVE');

    final result = await roll(
      const RolloutRequest(
        store: ReleaseStore.apple,
        action: RolloutAction.pause,
      ),
    );

    expect(result.state, 'PAUSED');
    expect(asc.phasedReleases[phased.id]!.state, 'PAUSED');
  });

  test("raises Google Play's staged rollout from 10 % to 50 %", () async {
    playServer.addApp(_package)
      ..addRelease('production', [3282])
      ..addRelease(
        'production',
        [3284],
        status: 'inProgress',
        name: '5.4.1',
        userFraction: 0.1,
      );

    final result = await roll(
      const RolloutRequest(
        store: ReleaseStore.play,
        action: RolloutAction.fraction,
        userFraction: 0.5,
      ),
    );

    expect(result.userFraction, 0.5);
    final track = playServer.apps[_package]!.tracks['production']!;
    expect(
      track.first.status,
      'completed',
      reason: 'the earlier release stays',
    );
    expect(track.last.status, 'inProgress');
    expect(track.last.userFraction, 0.5);
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
  Future<String> readDartDefines(String secretKey) =>
      throw StateError('This step reads no define file.');

  @override
  Future<String> writeSecretFile(String name, String contents) =>
      throw StateError('This step writes no secret file.');

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) => throw StateError('no process');
}
