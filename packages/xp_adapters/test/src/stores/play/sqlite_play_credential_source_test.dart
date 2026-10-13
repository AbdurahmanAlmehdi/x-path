import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/memory_secret_store.dart';

const _account = PlayServiceAccount(
  clientEmail: 'xpath@project.iam.gserviceaccount.com',
  privateKey: '-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----\n',
  privateKeyId: 'k1',
);

class _LockedSecrets extends MemorySecretStore {
  @override
  Future<String?> read(String key) =>
      throw const SecretsLockedException('The Keychain is locked.');
}

void main() {
  late SqliteDatabase database;
  late MemorySecretStore secrets;

  SqlitePlayCredentialSource source([SecretStore? store]) =>
      SqlitePlayCredentialSource(database: database, secrets: store ?? secrets);

  void addFlavor(String id, String? androidAppId) =>
      database.connection.execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, android_app_id) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, 'app_1', id, 'lib/main.dart', androidAppId],
      );

  void addCredential(String id, String flavor, String kind, String secretKey) =>
      database.connection.execute(
        'INSERT INTO credential_ref (id, flavor_id, kind, secret_key) '
        'VALUES (?, ?, ?, ?)',
        [id, flavor, kind, secretKey],
      );

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    secrets = MemorySecretStore();
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, default_base_branch) '
        "VALUES ('prj_1', 1, 'https://github.com/a/b.git', 'main')",
      )
      ..execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('app_1', 'prj_1', '.', 'flutter', 'sa')",
      );
    addFlavor('prod', 'com.mataa.app');
    addFlavor('dev', 'com.mataa.app.dev');
    addFlavor('ios_only', null);
    secrets.values['play.prod'] = _account.toSecret();
  });

  test('reads the account of the flavor with the application id', () async {
    addCredential('cred_1', 'prod', 'play_sa', 'play.prod');

    expect(await source().forAndroidAppId('com.mataa.app'), _account);
  });

  test('has no account for an application id without a reference', () async {
    addCredential('cred_1', 'prod', 'play_sa', 'play.prod');

    expect(await source().forAndroidAppId('com.mataa.app.dev'), isNull);
    expect(await source().forAndroidAppId('com.other'), isNull);
  });

  test('ignores references of other kinds', () async {
    addCredential('cred_1', 'prod', 'firebase_sa', 'play.prod');
    addCredential('cred_2', 'prod', 'asc_key', 'play.prod');

    expect(await source().forAndroidAppId('com.mataa.app'), isNull);
  });

  test('takes the oldest reference when there are two', () async {
    secrets.values['play.other'] = const PlayServiceAccount(
      clientEmail: 'other@x',
      privateKey: 'k',
    ).toSecret();
    addCredential('cred_b', 'prod', 'play_sa', 'play.prod');
    addCredential('cred_a', 'prod', 'play_sa', 'play.other');

    expect(
      (await source().forAndroidAppId('com.mataa.app'))!.clientEmail,
      'xpath@project.iam.gserviceaccount.com',
    );
  });

  test('has no account when the secret is missing or malformed', () async {
    addCredential('cred_1', 'prod', 'play_sa', 'play.missing');
    expect(await source().forAndroidAppId('com.mataa.app'), isNull);

    secrets.values['play.missing'] = '{"client_email": "a@b.c"}';
    expect(await source().forAndroidAppId('com.mataa.app'), isNull);
  });

  test('has no account when the secrets are locked', () async {
    addCredential('cred_1', 'prod', 'play_sa', 'play.prod');

    expect(
      await source(_LockedSecrets()).forAndroidAppId('com.mataa.app'),
      isNull,
    );
  });
}
