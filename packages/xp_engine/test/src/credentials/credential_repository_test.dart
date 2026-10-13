import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';

CredentialRecord _record(
  String id,
  CredentialKind kind, {
  CredentialFlavor flavor = testFlavor,
  String? secretKey,
}) => CredentialRecord(
  id: id,
  flavor: flavor,
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
  late InMemoryCredentialRepository repository;

  setUp(() => repository = InMemoryCredentialRepository([testFlavor, other]));

  test('finds a flavor by project, app path and name', () async {
    expect(await repository.findFlavor('prj_1', '.', 'prod'), testFlavor);
    expect(await repository.findFlavor('prj_2', 'apps/captain', 'dev'), other);
    expect(await repository.findFlavor('prj_1', '.', 'dev'), isNull);
    expect(await repository.findFlavor('prj_1', 'apps/x', 'prod'), isNull);
    expect(await repository.findFlavor('prj_9', '.', 'prod'), isNull);
  });

  test('saves, gets, finds and lists credentials', () async {
    await repository.save(_record('crd_1', CredentialKind.ascKey));
    await repository.save(_record('crd_2', CredentialKind.playSa));
    await repository.save(
      _record('crd_3', CredentialKind.slack, flavor: other),
    );

    expect((await repository.get('crd_2'))?.kind, CredentialKind.playSa);
    expect(await repository.get('nope'), isNull);
    expect(
      (await repository.find('flv_1', CredentialKind.ascKey))?.id,
      'crd_1',
    );
    expect(await repository.find('flv_1', CredentialKind.slack), isNull);
    expect(
      [for (final r in await repository.list()) r.id],
      ['crd_1', 'crd_2', 'crd_3'],
    );
    expect(
      [for (final r in await repository.list(projectId: 'prj_1')) r.id],
      ['crd_1', 'crd_2'],
    );
    expect(
      [for (final r in await repository.list(flavorId: 'flv_2')) r.id],
      ['crd_3'],
    );
  });

  test('saving again replaces the credential with that id', () async {
    await repository.save(_record('crd_1', CredentialKind.ascKey));
    await repository.save(
      _record('crd_1', CredentialKind.ascKey, secretKey: 'moved'),
    );

    expect(await repository.list(), hasLength(1));
    expect((await repository.get('crd_1'))?.secretKey, 'moved');
  });

  test('deletes and counts the credentials that share a secret', () async {
    await repository.save(
      _record('crd_1', CredentialKind.github, secretKey: 'github.token'),
    );
    await repository.save(
      _record(
        'crd_2',
        CredentialKind.github,
        flavor: other,
        secretKey: 'github.token',
      ),
    );

    expect(await repository.countUsing('github.token'), 2);
    expect(await repository.delete('crd_1'), isTrue);
    expect(await repository.delete('crd_1'), isFalse);
    expect(await repository.countUsing('github.token'), 1);
    expect(await repository.countUsing('other'), 0);
  });
}
