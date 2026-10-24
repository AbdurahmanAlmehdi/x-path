import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

WorkflowVersionRecord _version(String workflow, int number, [String? id]) =>
    WorkflowVersionRecord(
      id: id ?? 'wfv_${workflow}_$number',
      workflowId: workflow,
      version: number,
      yaml: 'schema: 1 # $number',
      createdAt: DateTime.utc(2026, 10, 13, number),
    );

void main() {
  late InMemoryWorkflowRepository repository;

  setUp(() async {
    repository = InMemoryWorkflowRepository();
    for (final (id, name, project) in [
      ('wf_b', 'b', 'prj_1'),
      ('wf_a', 'a', 'prj_1'),
      ('wf_c', 'c', 'prj_2'),
    ]) {
      await repository.create(
        WorkflowRecord(id: id, projectId: project, name: name, builtin: false),
        _version(id, 1),
      );
    }
  });

  test('lists the workflows of a project by name', () async {
    expect((await repository.list('prj_1')).map((w) => w.name), ['a', 'b']);
    expect((await repository.list('prj_2')).map((w) => w.name), ['c']);
    expect(await repository.list('prj_3'), isEmpty);
  });

  test('finds a workflow by id and by name', () async {
    expect((await repository.get('wf_a'))!.name, 'a');
    expect(await repository.get('wf_z'), isNull);
    expect((await repository.findByName('prj_1', 'b'))!.id, 'wf_b');
    expect(await repository.findByName('prj_2', 'b'), isNull);
  });

  test('numbers the versions from 1', () async {
    final second = await repository.addVersion(
      workflowId: 'wf_a',
      versionId: 'wfv_a2',
      yaml: 'y',
      createdAt: DateTime.utc(2026),
    );

    expect(second.version, 2);
    expect((await repository.versions('wf_a')).map((v) => v.version), [1, 2]);
    expect(await repository.versions('wf_z'), isEmpty);
    expect((await repository.versionById('wfv_a2'))!.yaml, 'y');
    expect(await repository.versionById('wfv_z'), isNull);
  });

  test('removes a workflow with its versions, unless jobs ran it', () async {
    repository.usedVersions.add('wfv_wf_b_1');

    await expectLater(
      repository.remove('wf_b'),
      throwsA(isA<WorkflowInUseException>()),
    );
    expect(await repository.remove('wf_a'), isTrue);
    expect(await repository.remove('wf_a'), isFalse);
    expect(await repository.versions('wf_a'), isEmpty);
  });

  test('updates a workflow, and a copy changes only what it is told', () async {
    final before = (await repository.get('wf_a'))!;
    final after = before.copyWith(
      name: 'renamed',
      archivedAt: () => DateTime.utc(2026, 10, 24),
      basedOnVersion: 4,
    );

    await repository.update(after);

    expect(await repository.get('wf_a'), after);
    expect(after.copyWith(), after);
    expect(after.copyWith(archivedAt: () => null).archivedAt, isNull);
    expect(after.basedOnBuiltin, before.basedOnBuiltin);
  });

  test('records compare by value', () {
    WorkflowRecord workflow(String id) =>
        WorkflowRecord(id: id, projectId: 'p', name: 'n', builtin: true);

    expect(workflow('w'), workflow('w'));
    expect(workflow('w'), isNot(workflow('x')));
    expect(_version('w', 1), _version('w', 1));
    expect(_version('w', 1), isNot(_version('w', 2)));
  });
}
