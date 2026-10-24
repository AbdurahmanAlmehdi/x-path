import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/memory_secret_store.dart';

const _key = AscKey(
  keyId: 'ABC123DEF4',
  issuerId: '57246542-96fe-1a63-e053-0824d011072a',
  privateKey: '-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----\n',
);

class _LockedSecrets extends MemorySecretStore {
  @override
  Future<String?> read(String key) =>
      throw const SecretsLockedException('The Keychain is locked.');
}

void main() {
  late SqliteDatabase database;
  late MemorySecretStore secrets;

  SqliteAscCredentialSource source([SecretStore? store]) =>
      SqliteAscCredentialSource(database: database, secrets: store ?? secrets);

  void addFlavor(String id, String? bundleId) => database.connection.execute(
    'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id) '
    'VALUES (?, ?, ?, ?, ?)',
    [id, 'app_1', id, 'lib/main.dart', bundleId],
  );

  void addCredential(String id, String flavor, String kind, String secretKey) =>
      database.connection
        ..execute(
          'INSERT INTO credential (id, name, kind, secret_key) '
          'VALUES (?, ?, ?, ?)',
          [id, id, kind, secretKey],
        )
        ..execute(
          'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
          'VALUES (?, ?, ?)',
          [flavor, kind, id],
        );

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    secrets = MemorySecretStore();
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
    addFlavor('prod', 'com.mataa.app');
    addFlavor('dev', 'com.mataa.app.dev');
    addFlavor('android_only', null);
    secrets.values['asc.prod'] = _key.toSecret();
  });

  test('reads the key of the flavor with the bundle id', () async {
    addCredential('cred_1', 'prod', 'asc_key', 'asc.prod');

    expect(await source().forBundleId('com.mataa.app'), _key);
  });

  test('has no key for a bundle id without a reference', () async {
    addCredential('cred_1', 'prod', 'asc_key', 'asc.prod');

    expect(await source().forBundleId('com.mataa.app.dev'), isNull);
    expect(await source().forBundleId('com.other'), isNull);
  });

  test('ignores references of other kinds (an Apple ID flavor)', () async {
    addCredential('cred_1', 'prod', 'apple_id', 'asc.prod');

    expect(await source().forBundleId('com.mataa.app'), isNull);
  });

  test('takes the oldest reference when two flavors share the id', () async {
    addFlavor('prod_b', 'com.mataa.app');
    secrets.values['asc.other'] = const AscKey(
      keyId: 'OTHER',
      issuerId: 'I',
      privateKey: 'p',
    ).toSecret();
    addCredential('cred_b', 'prod', 'asc_key', 'asc.prod');
    addCredential('cred_a', 'prod_b', 'asc_key', 'asc.other');

    expect((await source().forBundleId('com.mataa.app'))!.keyId, 'ABC123DEF4');
  });

  test('has no key when the secret is missing or malformed', () async {
    addCredential('cred_1', 'prod', 'asc_key', 'asc.missing');
    expect(await source().forBundleId('com.mataa.app'), isNull);

    secrets.values['asc.missing'] = '{"keyId": "K"}';
    expect(await source().forBundleId('com.mataa.app'), isNull);
  });

  test('has no key when the secrets are locked', () async {
    addCredential('cred_1', 'prod', 'asc_key', 'asc.prod');

    expect(await source(_LockedSecrets()).forBundleId('com.mataa.app'), isNull);
  });
}
