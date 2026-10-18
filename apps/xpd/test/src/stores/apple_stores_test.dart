import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/job_fakes.dart';

const _bundleId = 'com.mataa.app';

void main() {
  late ManualClock clock;
  late SqliteDatabase database;
  late MemorySecretStore secrets;
  late FakeAscServer server;
  late AppleStores apple;

  void addFlavor(String id, String bundleId, {String? credentialKind}) {
    database.connection.execute(
      'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, 'app_1', id, 'lib/main.dart', bundleId],
    );
    if (credentialKind != null) {
      database.connection
        ..execute(
          'INSERT INTO credential (id, name, kind, secret_key) '
          'VALUES (?, ?, ?, ?)',
          ['cred_$id', 'cred_$id', credentialKind, 'asc.$id'],
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
        'INSERT INTO project (id, github_repo_id, remote, default_base_branch) '
        "VALUES ('prj_1', 1, 'https://github.com/a/b.git', 'main')",
      )
      ..execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('app_1', 'prj_1', '.', 'flutter', 'sa')",
      );
    secrets = MemorySecretStore();
    server = await FakeAscServer.start(now: clock.now);
    addTearDown(server.close);
    apple = AppleStores(
      database: database,
      secrets: secrets,
      clock: clock,
      ascBaseUrl: server.baseUrl,
      itunesBaseUrl: server.baseUrl,
    );
    addTearDown(apple.close);
  });

  test('reads the iTunes lookup of the storefront for a release', () async {
    server.addItunes(_bundleId, version: '2.0.0', country: 'sa');

    final app = await apple.itunes.lookup(bundleId: _bundleId, country: 'sa');

    expect(app!.version, '2.0.0');
  });

  group('a flavor with an asc_key credential', () {
    setUp(() {
      addFlavor('prod', _bundleId, credentialKind: 'asc_key');
      secrets.values['asc.prod'] = const AscKey(
        keyId: fakeAscKeyId,
        issuerId: fakeAscIssuerId,
        privateKey: fakeAscPrivateKeyPem,
      ).toSecret();
      final app = server.addApp(_bundleId);
      server
        ..addVersion(app.id, '5.4.0', appVersionState: 'READY_FOR_DISTRIBUTION')
        ..addVersion(
          app.id,
          '5.4.1',
          appVersionState: 'PENDING_DEVELOPER_RELEASE',
        )
        ..addBuild(app.id, buildNumber: '3282', version: '5.4.0')
        ..addBuild(app.id, buildNumber: '3283', version: '5.4.1')
        ..addItunes(_bundleId, version: '5.4.0', country: 'sa');
    });

    test('knows the live version and the closed train', () async {
      final status = await apple.trains.status(
        bundleId: _bundleId,
        country: 'sa',
      );

      expect(status!.liveVersion, VersionName.parse('5.4.0'));
      expect(status.closedVersions, {VersionName.parse('5.4.1')});
      expect(server.requests.where((r) => r.tokenProblem != null), isEmpty);
    });

    test('knows the build numbers Apple has seen', () async {
      final builds = await apple.buildNumbers.lookup(
        iosBundleId: _bundleId,
        androidAppId: _bundleId,
      );

      expect(builds, const StoreBuilds({3282, 3283}));
    });

    test('keeps one client, and its token, per key', () async {
      final key = (await apple.credentials.forBundleId(_bundleId))!;

      expect(apple.connect(key), same(apple.connect(key)));
    });
  });

  group('a flavor without an API key (Apple ID)', () {
    setUp(() {
      addFlavor('prod', _bundleId, credentialKind: 'apple_id');
      server.addItunes(_bundleId, version: '5.4.0', country: 'sa');
    });

    test('gets the iTunes lookup only', () async {
      final status = await apple.trains.status(
        bundleId: _bundleId,
        country: 'sa',
      );

      expect(
        status,
        AppStoreTrainStatus(liveVersion: VersionName.parse('5.4.0')),
      );
      expect(server.requests.map((r) => r.uri.path), ['/lookup']);
    });

    test('cannot tell the build numbers', () async {
      expect(await apple.buildNumbers.lookup(iosBundleId: _bundleId), isNull);
    });
  });

  test('wires the appStoreTrain check', () {
    expect(apple.guardChecks.map((check) => check.name), [
      GuardCheckName.appStoreTrain,
    ]);
  });

  test('wires the upload.appStore step', () {
    final step = apple.uploadStep(
      repository: InMemoryArtifactRepository(),
      store: _Store(),
      secrets: secrets,
      secretFiles: InMemorySecretFileStore(),
      isMacOS: true,
    );

    expect(step.kind, 'upload.appStore');
    expect(step.connect, apple.connect);
  });
}

class _Store extends InMemoryArtifactStore implements LocalArtifactStore {
  @override
  String localPath(String path) => '/artifacts/$path';
}
