import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';
import 'package:xp_fake_play/xp_fake_play.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/job_fakes.dart';

const _bundleId = 'com.mataa.app';
const _package = 'com.mataa.app';

void main() {
  late ManualClock clock;
  late SqliteDatabase database;
  late MemorySecretStore secrets;
  late FakeAscServer asc;
  late FakePlayServer playServer;
  late AppleStores apple;
  late PlayStores play;
  late List<GuardCheck> checks;

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, default_base_branch) '
        "VALUES ('prj_1', 1, 'https://github.com/a/b.git', 'main')",
      )
      ..execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('app_1', 'prj_1', '.', 'flutter', 'sa')",
      )
      ..execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id, '
        "android_app_id) VALUES ('prod', 'app_1', 'prod', 'lib/main.dart', ?, ?)",
        [_bundleId, _package],
      )
      ..execute(
        'INSERT INTO credential_ref (id, flavor_id, kind, secret_key) VALUES '
        "('c1', 'prod', 'asc_key', 'asc.prod'), "
        "('c2', 'prod', 'play_sa', 'play.prod')",
      );
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
    );
    addTearDown(play.close);
    checks = storeGuardChecks(apple: apple, play: play);
  });

  test('are the three checks that ask the stores', () {
    expect(checks.map((check) => check.name), [
      GuardCheckName.appStoreTrain,
      GuardCheckName.playTargetSdk,
      GuardCheckName.buildNumberReuse,
    ]);
  });

  group('buildNumberReuse', () {
    late BuildNumberReuseCheck reuse;
    late CombinedStoreBuildNumbers numbers;

    setUp(() {
      reuse = checks.last as BuildNumberReuseCheck;
      numbers = CombinedStoreBuildNumbers(
        apple: apple.buildNumbers,
        play: play.buildNumbers,
      );
    });

    test('knows the build numbers of both stores', () async {
      final app = asc.addApp(_bundleId);
      asc.addBuild(app.id, buildNumber: '3282', version: '5.4.0');
      playServer.addApp(_package).addRelease('production', [3283]);

      final builds = await numbers.lookup(
        iosBundleId: _bundleId,
        androidAppId: _package,
      );

      expect(reuse.name, GuardCheckName.buildNumberReuse);
      expect(builds, const StoreBuilds({3282, 3283}));
    });

    test('names the store it could not read', () async {
      asc.addApp(_bundleId);
      // Play has no such app.

      final builds = await numbers.lookup(
        iosBundleId: _bundleId,
        androidAppId: _package,
      );

      expect(builds, const StoreBuilds({}, unreadable: {'Google Play'}));
    });
  });
}
