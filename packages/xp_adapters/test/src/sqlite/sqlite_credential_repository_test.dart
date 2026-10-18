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
    projectName: 'acme/shop',
    appPath: '.',
    name: 'prod',
    iosBundleId: 'com.mataa.app',
    androidAppId: 'com.mataa.app',
  );
  const beta = CredentialFlavor(
    id: 'flv_beta',
    projectId: 'prj_1',
    projectName: 'acme/shop',
    appPath: '.',
    name: 'beta',
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
    String? name,
    String? secretKey,
  }) => CredentialRecord(
    id: id,
    name: name ?? id,
    kind: kind,
    secretKey: secretKey ?? 'credential.$id',
  );

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteCredentialRepository(database);
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, default_base_branch, '
        'full_name) VALUES '
        "('prj_1', 1, 'a', 'main', 'acme/shop'), ('prj_2', 2, 'b', 'main', '')",
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
        "('flv_beta', 'app_1', 'beta', 'lib/main.dart', NULL, NULL), "
        "('flv_dev', 'app_2', 'dev', 'lib/main_dev.dart', NULL, NULL)",
      );
  });

  test('finds a flavor by project, app path and name', () async {
    expect(await repository.findFlavor('prj_1', '.', 'prod'), prod);
    expect(await repository.findFlavor('prj_2', 'apps/captain', 'dev'), dev);
    expect(await repository.findFlavor('prj_1', '.', 'dev'), isNull);
    expect(await repository.findFlavor('prj_2', '.', 'dev'), isNull);
  });

  test('lists the flavors of an app by name', () async {
    expect(await repository.flavorsOf('prj_1', '.'), [beta, prod]);
    expect(await repository.flavorsOf('prj_2', '.'), isEmpty);
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
    expect(await repository.get('crd_9'), isNull);
  });

  test('updates a credential in place: name, secret and check', () async {
    await repository.save(record('crd_1', CredentialKind.shorebird));
    final updated = record(
      'crd_1',
      CredentialKind.shorebird,
      name: 'Studio',
      secretKey: 'other',
    ).checked(status: CredentialStatus.verified, at: checked);

    await repository.save(updated);

    expect(await repository.get('crd_1'), updated);
    expect(await repository.list(), [updated]);
  });

  test('lists by name regardless of case and finds by name', () async {
    await repository.save(record('crd_1', CredentialKind.slack, name: 'beta'));
    await repository.save(record('crd_2', CredentialKind.slack, name: 'Alpha'));
    await repository.save(
      record('crd_3', CredentialKind.slack, name: 'Équipe'),
    );

    expect(
      [for (final r in await repository.list()) r.name],
      ['Alpha', 'beta', 'Équipe'],
    );
    expect((await repository.findByName('ALPHA'))?.id, 'crd_2');
    expect((await repository.findByName('équipe'))?.id, 'crd_3');
    expect(await repository.findByName('gamma'), isNull);
  });

  test('refuses a second credential with the same name in any case', () async {
    await repository.save(record('crd_1', CredentialKind.slack, name: 'Team'));

    expect(
      () =>
          repository.save(record('crd_2', CredentialKind.slack, name: 'TEAM')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('assigns, finds and lists by place', () async {
    final key = record('crd_1', CredentialKind.ascKey, name: 'Key');
    final slack = record('crd_2', CredentialKind.slack, name: 'Slack');
    await repository.save(key);
    await repository.save(slack);
    final assigned = AssignedCredential(flavor: prod, credential: key).checked(
      status: CredentialStatus.rejected,
      at: checked,
      message: 'No app.',
      fix: 'Create it.',
    );
    await repository.assign(assigned);
    await repository.assign(AssignedCredential(flavor: beta, credential: key));
    await repository.assign(AssignedCredential(flavor: dev, credential: slack));
    await repository.assign(
      AssignedCredential(flavor: prod, credential: slack),
    );

    expect(
      await repository.assignment('flv_prod', CredentialKind.ascKey),
      assigned,
    );
    expect(
      await repository.assignment('flv_dev', CredentialKind.ascKey),
      isNull,
    );
    String place(AssignedCredential a) => '${a.flavor.id} ${a.kind.wire}';
    expect((await repository.assignments()).map(place), [
      'flv_beta asc_key',
      'flv_prod asc_key',
      'flv_prod slack',
      'flv_dev slack',
    ]);
    expect(
      (await repository.assignments(projectId: 'prj_2')).single.flavor,
      dev,
      reason: 'a project without a full name has no project name',
    );
    expect((await repository.assignments(flavorId: 'flv_prod')).map(place), [
      'flv_prod asc_key',
      'flv_prod slack',
    ]);
    expect(
      (await repository.assignments(
        projectId: 'prj_1',
        credentialId: 'crd_2',
      )).map(place),
      ['flv_prod slack'],
    );
  });

  test('moves a flavor to another credential of the kind', () async {
    final one = record('crd_1', CredentialKind.ascKey, name: 'One');
    final two = record('crd_2', CredentialKind.ascKey, name: 'Two');
    await repository.save(one);
    await repository.save(two);
    await repository.assign(AssignedCredential(flavor: prod, credential: one));

    await repository.assign(AssignedCredential(flavor: prod, credential: two));

    expect(
      (await repository.assignment('flv_prod', CredentialKind.ascKey))!.id,
      'crd_2',
    );
  });

  test('refuses to assign a credential to another kind', () async {
    final key = record('crd_1', CredentialKind.ascKey);
    await repository.save(key);

    expect(
      () => database.connection.execute(
        'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
        "VALUES ('flv_prod', 'slack', 'crd_1')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('unassigns', () async {
    final key = record('crd_1', CredentialKind.ascKey);
    await repository.save(key);
    await repository.assign(AssignedCredential(flavor: prod, credential: key));

    expect(
      await repository.unassign('flv_prod', CredentialKind.ascKey),
      isTrue,
    );
    expect(
      await repository.unassign('flv_prod', CredentialKind.ascKey),
      isFalse,
    );
    expect(await repository.get('crd_1'), isNotNull);
  });

  test('deletes a credential with its assignments', () async {
    final key = record('crd_1', CredentialKind.ascKey);
    await repository.save(key);
    await repository.assign(AssignedCredential(flavor: prod, credential: key));

    expect(await repository.delete('crd_1'), isTrue);
    expect(await repository.delete('crd_1'), isFalse);
    expect(await repository.assignments(), isEmpty);
  });

  test('a flavor that goes takes its assignments with it', () async {
    final key = record('crd_1', CredentialKind.ascKey);
    await repository.save(key);
    await repository.assign(AssignedCredential(flavor: dev, credential: key));

    database.connection.execute("DELETE FROM flavor WHERE id = 'flv_dev'");

    expect(await repository.assignments(), isEmpty);
    expect(await repository.get('crd_1'), isNotNull);
  });

  test('counts the credentials that keep a secret under a key', () async {
    await repository.save(
      record('crd_1', CredentialKind.ascKey, name: 'a', secretKey: 'shared'),
    );
    await repository.save(
      record('crd_2', CredentialKind.ascKey, name: 'b', secretKey: 'shared'),
    );

    expect(await repository.countUsing('shared'), 2);
    expect(await repository.countUsing('nothing'), 0);
  });
}
