import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late SqliteDatabase database;
  late SqliteCredentialRepository repository;
  final checked = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

  const prod = CredentialFlavor(
    id: 'flv_prod',
    projectId: 'prj_1',
    appPath: '.',
    name: 'prod',
    iosBundleId: 'com.mataa.app',
    androidAppId: 'com.mataa.app',
  );
  const dev = CredentialFlavor(
    id: 'flv_dev',
    projectId: 'prj_2',
    appPath: 'apps/captain',
    name: 'dev',
  );

  CredentialRecord record(
    String id,
    CredentialKind kind, {
    CredentialFlavor flavor = prod,
    String? secretKey,
  }) => CredentialRecord(
    id: id,
    flavor: flavor,
    kind: kind,
    secretKey: secretKey ?? 'credential.$id',
  );

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteCredentialRepository(database);
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, default_base_branch) '
        "VALUES ('prj_1', 1, 'a', 'main'), ('prj_2', 2, 'b', 'main')",
      )
      ..execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('app_1', 'prj_1', '.', 'flutter', 'us'), "
        "('app_2', 'prj_2', 'apps/captain', 'flutter', 'ly')",
      )
      ..execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id, '
        'android_app_id) VALUES '
        "('flv_prod', 'app_1', 'prod', 'lib/main.dart', 'com.mataa.app', "
        "'com.mataa.app'), "
        "('flv_dev', 'app_2', 'dev', 'lib/main_dev.dart', NULL, NULL)",
      );
  });

  test('finds a flavor by project, app path and name', () async {
    expect(await repository.findFlavor('prj_1', '.', 'prod'), prod);
    expect(await repository.findFlavor('prj_2', 'apps/captain', 'dev'), dev);
    expect(await repository.findFlavor('prj_1', '.', 'dev'), isNull);
    expect(await repository.findFlavor('prj_2', '.', 'dev'), isNull);
  });

  test('stores a credential with its check and reads it back', () async {
    final stored = record('crd_1', CredentialKind.ascKey).checked(
      status: CredentialStatus.rejected,
      at: checked,
      account: 'ABC123DEF4',
      message: 'Revoked.',
      fix: 'Replace it.',
    );

    await repository.save(stored);

    expect(await repository.get('crd_1'), stored);
    expect(await repository.find('flv_prod', CredentialKind.ascKey), stored);
  });

  test(
    'keeps the time of the last acceptance apart from the last check',
    () async {
      final accepted = record(
        'crd_1',
        CredentialKind.ascKey,
      ).checked(status: CredentialStatus.verified, at: checked);
      final refused = accepted.checked(
        status: CredentialStatus.rejected,
        at: checked.add(const Duration(days: 1)),
        message: 'Revoked.',
      );

      await repository.save(refused);

      final read = (await repository.get('crd_1'))!;
      expect(read.verifiedAt, checked);
      expect(read.checkedAt, checked.add(const Duration(days: 1)));
    },
  );

  test('reads a credential that was never checked', () async {
    await repository.save(record('crd_1', CredentialKind.slack));

    final read = (await repository.get('crd_1'))!;

    expect(read.status, CredentialStatus.unverified);
    expect(read.checkedAt, isNull);
    expect(read.verifiedAt, isNull);
    expect(read.account, isNull);
  });

  test('saving again replaces the reference with that id', () async {
    await repository.save(record('crd_1', CredentialKind.shorebird));
    await repository.save(
      record(
        'crd_1',
        CredentialKind.shorebird,
        secretKey: 'moved',
      ).checked(status: CredentialStatus.verified, at: checked, account: 'me'),
    );

    final all = await repository.list();
    expect(all, hasLength(1));
    expect(all.single.secretKey, 'moved');
    expect(all.single.account, 'me');
  });

  test('a flavor has one credential of each kind', () async {
    await repository.save(record('crd_1', CredentialKind.ascKey));

    await expectLater(
      repository.save(record('crd_2', CredentialKind.ascKey)),
      throwsA(isA<SqliteException>()),
    );
    await repository.save(record('crd_3', CredentialKind.playSa));
    expect(await repository.list(), hasLength(2));
  });

  test('lists oldest first, for a flavor, a project or all', () async {
    await repository.save(record('crd_1', CredentialKind.ascKey));
    await repository.save(record('crd_2', CredentialKind.slack, flavor: dev));
    await repository.save(record('crd_3', CredentialKind.playSa));

    List<String> ids(List<CredentialRecord> records) => [
      for (final r in records) r.id,
    ];
    expect(ids(await repository.list()), ['crd_1', 'crd_2', 'crd_3']);
    expect(ids(await repository.list(projectId: 'prj_1')), ['crd_1', 'crd_3']);
    expect(ids(await repository.list(flavorId: 'flv_dev')), ['crd_2']);
    expect(
      ids(await repository.list(projectId: 'prj_2', flavorId: 'flv_prod')),
      isEmpty,
    );
    expect((await repository.list(flavorId: 'flv_dev')).single.flavor, dev);
  });

  test('gets and finds nothing that is not there', () async {
    expect(await repository.get('nope'), isNull);
    expect(await repository.find('flv_prod', CredentialKind.github), isNull);
  });

  test('deletes a credential', () async {
    await repository.save(record('crd_1', CredentialKind.ascKey));

    expect(await repository.delete('crd_1'), isTrue);
    expect(await repository.delete('crd_1'), isFalse);
    expect(await repository.list(), isEmpty);
  });

  test('counts the credentials that keep a secret under one key', () async {
    await repository.save(
      record('crd_1', CredentialKind.github, secretKey: 'github.token'),
    );
    await repository.save(
      record(
        'crd_2',
        CredentialKind.github,
        flavor: dev,
        secretKey: 'github.token',
      ),
    );

    expect(await repository.countUsing('github.token'), 2);
    expect(await repository.countUsing('credential.crd_9'), 0);
  });

  test('a flavor that goes takes its credentials with it', () async {
    await repository.save(record('crd_1', CredentialKind.ascKey));

    database.connection.execute("DELETE FROM flavor WHERE id = 'flv_prod'");

    expect(await repository.list(), isEmpty);
  });

  test('refuses a status the table does not know', () {
    expect(
      () => database.connection.execute(
        'INSERT INTO credential_ref (id, flavor_id, kind, secret_key, status) '
        "VALUES ('x', 'flv_prod', 'slack', 'k', 'bad')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
