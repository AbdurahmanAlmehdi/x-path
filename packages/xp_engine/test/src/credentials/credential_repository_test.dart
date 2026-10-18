import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';

CredentialRecord _record(
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

void main() {
  const other = CredentialFlavor(
    id: 'flv_2',
    projectId: 'prj_2',
    appPath: 'apps/captain',
    name: 'dev',
  );
  const sibling = CredentialFlavor(
    id: 'flv_3',
    projectId: 'prj_1',
    appPath: '.',
    name: 'dev',
  );
  late InMemoryCredentialRepository repository;

  setUp(
    () =>
        repository = InMemoryCredentialRepository([testFlavor, other, sibling]),
  );

  test('finds a flavor by project, app path and name', () async {
    expect(await repository.findFlavor('prj_1', '.', 'prod'), testFlavor);
    expect(await repository.findFlavor('prj_2', 'apps/captain', 'dev'), other);
    expect(await repository.findFlavor('prj_1', 'apps/x', 'prod'), isNull);
    expect(await repository.findFlavor('prj_9', '.', 'prod'), isNull);
  });

  test('lists the flavors of an app by name', () async {
    expect(await repository.flavorsOf('prj_1', '.'), [sibling, testFlavor]);
    expect(await repository.flavorsOf('prj_1', 'apps/captain'), isEmpty);
  });

  test('saves, gets and lists credentials by name, any case', () async {
    await repository.save(_record('crd_1', CredentialKind.ascKey, name: 'b'));
    await repository.save(_record('crd_2', CredentialKind.playSa, name: 'A'));

    expect((await repository.get('crd_2'))?.kind, CredentialKind.playSa);
    expect(await repository.get('nope'), isNull);
    expect((await repository.findByName('B'))?.id, 'crd_1');
    expect(await repository.findByName('c'), isNull);
    expect([for (final r in await repository.list()) r.id], ['crd_2', 'crd_1']);
  });

  test('refuses a name another credential has', () async {
    await repository.save(_record('crd_1', CredentialKind.ascKey, name: 'K'));

    expect(
      () => repository.save(_record('crd_2', CredentialKind.ascKey, name: 'k')),
      throwsStateError,
    );
    await repository.save(_record('crd_1', CredentialKind.ascKey, name: 'k'));
    expect((await repository.get('crd_1'))?.name, 'k');
  });

  test('assigns, finds and lists by flavor, credential and project', () async {
    final key = _record('crd_1', CredentialKind.ascKey);
    final slack = _record('crd_2', CredentialKind.slack);
    await repository.save(key);
    await repository.save(slack);
    await repository.assign(
      AssignedCredential(flavor: testFlavor, credential: key),
    );
    await repository.assign(
      AssignedCredential(flavor: sibling, credential: key),
    );
    await repository.assign(
      AssignedCredential(flavor: other, credential: slack),
    );
    await repository.assign(
      AssignedCredential(flavor: testFlavor, credential: slack),
    );

    expect(
      (await repository.assignment('flv_1', CredentialKind.ascKey))?.id,
      'crd_1',
    );
    expect(await repository.assignment('flv_2', CredentialKind.ascKey), isNull);
    String place(AssignedCredential a) => '${a.flavor.id}:${a.kind.wire}';
    expect((await repository.assignments()).map(place), [
      'flv_3:asc_key',
      'flv_1:asc_key',
      'flv_1:slack',
      'flv_2:slack',
    ]);
    expect((await repository.assignments(projectId: 'prj_1')).map(place), [
      'flv_3:asc_key',
      'flv_1:asc_key',
      'flv_1:slack',
    ]);
    expect((await repository.assignments(flavorId: 'flv_1')).map(place), [
      'flv_1:asc_key',
      'flv_1:slack',
    ]);
    expect((await repository.assignments(credentialId: 'crd_2')).map(place), [
      'flv_1:slack',
      'flv_2:slack',
    ]);
  });

  test('gives assignments the newest state of their credential', () async {
    final key = _record('crd_1', CredentialKind.ascKey);
    await repository.put(
      AssignedCredential(flavor: testFlavor, credential: key),
    );
    await repository.save(key.renamed('Renamed'));

    expect(
      (await repository.assignment(
        'flv_1',
        CredentialKind.ascKey,
      ))!.credential.name,
      'Renamed',
    );
    expect((await repository.assignments()).single.credential.name, 'Renamed');
  });

  test('refuses to assign a credential it does not know', () async {
    expect(
      () => repository.assign(
        AssignedCredential(
          flavor: testFlavor,
          credential: _record('crd_9', CredentialKind.ascKey),
        ),
      ),
      throwsStateError,
    );
  });

  test('unassigns', () async {
    await repository.put(
      AssignedCredential(
        flavor: testFlavor,
        credential: _record('crd_1', CredentialKind.ascKey),
      ),
    );

    expect(await repository.unassign('flv_1', CredentialKind.ascKey), isTrue);
    expect(await repository.unassign('flv_1', CredentialKind.ascKey), isFalse);
    expect(await repository.get('crd_1'), isNotNull);
  });

  test('deletes a credential with its assignments', () async {
    await repository.put(
      AssignedCredential(
        flavor: testFlavor,
        credential: _record('crd_1', CredentialKind.ascKey),
      ),
    );

    expect(await repository.delete('crd_1'), isTrue);
    expect(await repository.delete('crd_1'), isFalse);
    expect(await repository.assignments(), isEmpty);
  });

  test('counts the credentials that share a secret', () async {
    await repository.save(
      _record('crd_1', CredentialKind.ascKey, secretKey: 'shared'),
    );
    await repository.save(
      _record('crd_2', CredentialKind.ascKey, secretKey: 'shared'),
    );

    expect(await repository.countUsing('shared'), 2);
    expect(await repository.countUsing('none'), 0);
  });
}
