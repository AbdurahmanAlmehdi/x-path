import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/all_steps.dart';
import '../../helpers/workflow_fixtures.dart';

const _simple = '''
schema: 1
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: guard
            with:
              checks: [source]
''';

void main() {
  late InMemoryWorkflowRepository repository;
  late InMemoryProjectRepository projects;
  late InMemoryEventLog events;
  late ManualClock clock;
  late WorkflowService service;

  setUp(() async {
    repository = InMemoryWorkflowRepository();
    projects = InMemoryProjectRepository();
    await projects.add(demoProject());
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    events = InMemoryEventLog(clock: clock);
    service = WorkflowService(
      repository: repository,
      projects: projects,
      catalog: StepPlanners(allSteps()),
      events: events,
      clock: clock,
      random: Random(1),
    );
  });

  Future<List<EngineEvent>> logged() async {
    final seen = <EngineEvent>[];
    final subscription = events
        .subscribe(after: 0)
        .listen((e) => seen.add(e.event));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return seen;
  }

  group('list', () {
    test('makes the built-in workflows of the project, by name', () async {
      final workflows = await service.list('prj_1');

      expect(workflows.map((w) => w.name), [
        'dev-build',
        'prod-release',
        'release-merge',
        'shorebird-patch',
        'test',
      ]);
      expect(workflows.every((w) => w.builtin), isTrue);
      expect(workflows.every((w) => w.version.version == 1), isTrue);
      expect(workflows.first.id, startsWith('wf_'));
      expect(workflows.first.version.id, startsWith('wfv_'));
      expect(workflows.first.title, 'Dev build');
      expect(workflows.first.description, startsWith('Builds the dev flavors'));
      expect(await logged(), isEmpty);
    });

    test('makes them once', () async {
      final first = await service.list('prj_1');
      final second = await service.list('prj_1');

      expect(second, first);
    });

    test(
      'gives a built-in a new version when the engine ships another',
      () async {
        final workflows = await service.list('prj_1');
        final test = workflows.firstWhere((w) => w.name == 'test');
        await repository.addVersion(
          workflowId: test.id,
          versionId: 'wfv_old',
          yaml: 'schema: 1\n# an older document\n',
          createdAt: DateTime.utc(2026),
        );

        final after = await service.list('prj_1');

        expect(after.firstWhere((w) => w.name == 'test').version.version, 3);
        expect(
          (await service.get('prj_1', test.id)).yaml,
          builtinWorkflows['test'],
        );
      },
    );

    test(
      'leaves a workflow of the owner that has a built-in name alone',
      () async {
        await repository.create(
          const WorkflowRecord(
            id: 'wf_mine',
            projectId: 'prj_1',
            name: 'dev-build',
            builtin: false,
          ),
          WorkflowVersionRecord(
            id: 'wfv_mine',
            workflowId: 'wf_mine',
            version: 1,
            yaml: _simple,
            createdAt: DateTime.utc(2026),
          ),
        );

        final workflows = await service.list('prj_1');

        final mine = workflows.firstWhere((w) => w.name == 'dev-build');
        expect(mine.id, 'wf_mine');
        expect(mine.builtin, isFalse);
        expect(mine.version.version, 1);
      },
    );

    test('needs a project', () async {
      await expectLater(
        service.list('prj_nope'),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });
  });

  group('get', () {
    test('shows the newest version, or the one asked for', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );
      final second = await service.save('prj_1', created.id, '$_simple# two\n');

      final newest = await service.get('prj_1', created.id);
      final first = await service.get('prj_1', created.id, version: 1);

      expect(newest.version.version, 2);
      expect(newest.yaml, '$_simple# two\n');
      expect(newest.versions.map((v) => v.version), [1, 2]);
      expect(first.version.version, 1);
      expect(first.yaml, _simple);
      expect(second.version.id, newest.version.id);
      expect(newest.builtin, isFalse);
    });

    test('reads the inputs its version declares, typed', () async {
      await service.list('prj_1');
      final patch = (await service.list('prj_1'))
          .firstWhere((workflow) => workflow.name == 'shorebird-patch');

      final inputs = (await service.get('prj_1', patch.id)).inputs;

      expect(inputs.first, isA<WorkflowInput>());
      expect({
        for (final input in inputs) input.name: input.type,
      }, containsPair('releaseVersion', InputType.release));
      expect({
        for (final input in inputs) input.name: input.type,
      }, containsPair('allowNativeDiffs', InputType.boolean));
      final plain = await service.create('prj_1', name: 'plain', yaml: _simple);
      expect((await service.get('prj_1', plain.id)).inputs, isEmpty);
      // A version saved before this engine's rules reads without inputs.
      await repository.addVersion(
        workflowId: plain.id,
        versionId: 'wfv_old',
        yaml: 'schema: 1\ninputs:\n  a: {type: nope}\n',
        createdAt: DateTime.utc(2026),
      );
      expect((await service.get('prj_1', plain.id)).inputs, isEmpty);
    });

    test('says when there is no such version or workflow', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );

      await expectLater(
        service.get('prj_1', created.id, version: 9),
        throwsA(
          isA<WorkflowNotFoundException>()
              .having((e) => e.version, 'version', 9)
              .having((e) => e.message, 'message', contains('no version 9')),
        ),
      );
      await expectLater(
        service.get('prj_1', 'wf_nope'),
        throwsA(
          isA<WorkflowNotFoundException>().having(
            (e) => e.message,
            'message',
            'There is no workflow wf_nope in this project.',
          ),
        ),
      );
    });

    test('does not show the workflow of another project', () async {
      await projects.add(demoProject(id: 'prj_2', repoId: 43));
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );

      await expectLater(
        service.get('prj_2', created.id),
        throwsA(isA<WorkflowNotFoundException>()),
      );
    });
  });

  group('create', () {
    test('stores version 1 and announces it', () async {
      final workflow = await service.create(
        'prj_1',
        name: 'my.flow_1',
        yaml: _simple,
      );

      expect(workflow.name, 'my.flow_1');
      expect(workflow.builtin, isFalse);
      expect(workflow.version.version, 1);
      expect(workflow.version.createdAt, DateTime.utc(2026, 10, 13, 9));
      expect(await logged(), [
        WorkflowSaved(
          workflowId: workflow.id,
          projectId: 'prj_1',
          name: 'my.flow_1',
          version: 1,
        ),
      ]);
    });

    test('refuses a name that is not allowed', () async {
      for (final name in ['', '-a', 'a b', 'a/b', 'x' * 65]) {
        await expectLater(
          service.create('prj_1', name: name, yaml: _simple),
          throwsA(isA<WorkflowNameException>()),
          reason: name,
        );
      }
    });

    test('refuses a name that is used, built-ins included', () async {
      await service.create('prj_1', name: 'mine', yaml: _simple);

      for (final name in ['mine', 'dev-build']) {
        await expectLater(
          service.create('prj_1', name: name, yaml: _simple),
          throwsA(
            isA<WorkflowExistsException>().having((e) => e.name, 'name', name),
          ),
        );
      }
    });

    test('refuses a document with issues, and lists them', () async {
      await expectLater(
        service.create('prj_1', name: 'bad', yaml: 'schema: 1\nstages: []'),
        throwsA(
          isA<WorkflowInvalidException>()
              .having((e) => e.issues, 'issues', hasLength(1))
              .having(
                (e) => e.message,
                'message',
                'The workflow has 1 issue: line 2, column 9: "stages" is a '
                    'list with at least one stage.',
              ),
        ),
      );
      await expectLater(
        service.create('prj_1', name: 'bad', yaml: 'x: 1'),
        throwsA(
          isA<WorkflowInvalidException>().having(
            (e) => e.message,
            'message',
            startsWith('The workflow has 3 issues: '),
          ),
        ),
      );
      expect(
        (await service.list('prj_1')).map((w) => w.name),
        isNot(contains('bad')),
      );
    });
  });

  group('copies of built-ins', () {
    test('remember the built-in and its version', () async {
      final copy = await service.create(
        'prj_1',
        name: 'my-dev',
        yaml: _simple,
        basedOn: const WorkflowBasedOn(builtin: 'dev-build', version: 1),
      );

      const basedOn = WorkflowBasedOn(builtin: 'dev-build', version: 1);
      expect(copy.basedOn, basedOn);
      expect(
        (await service.list('prj_1'))
            .firstWhere((w) => w.id == copy.id)
            .basedOn,
        basedOn,
      );
    });

    test('refuse a built-in that does not exist', () async {
      await expectLater(
        service.create(
          'prj_1',
          name: 'mine',
          yaml: _simple,
          basedOn: const WorkflowBasedOn(builtin: 'nope', version: 1),
        ),
        throwsA(
          isA<WorkflowEditException>().having(
            (e) => e.toString(),
            'toString',
            'WorkflowEditException: "nope" is not a built-in workflow.',
          ),
        ),
      );
    });
  });

  group('update', () {
    late Workflow mine;

    setUp(() async {
      mine = await service.create('prj_1', name: 'mine', yaml: _simple);
    });

    test('renames, without a new version, and announces it', () async {
      final renamed = await service.update(
        'prj_1',
        mine.id,
        const UpdateWorkflowRequest(name: 'nightly'),
      );

      expect(renamed.name, 'nightly');
      expect(renamed.versions, hasLength(1));
      expect(
        await logged(),
        contains(
          WorkflowUpdated(
            workflowId: mine.id,
            projectId: 'prj_1',
            name: 'nightly',
            archived: false,
          ),
        ),
      );
    });

    test('refuses a name that is not allowed or used', () async {
      await expectLater(
        service.update(
          'prj_1',
          mine.id,
          const UpdateWorkflowRequest(name: 'a b'),
        ),
        throwsA(isA<WorkflowNameException>()),
      );
      await expectLater(
        service.update(
          'prj_1',
          mine.id,
          const UpdateWorkflowRequest(name: 'dev-build'),
        ),
        throwsA(isA<WorkflowExistsException>()),
      );
      expect(
        (await service.update(
          'prj_1',
          mine.id,
          const UpdateWorkflowRequest(name: 'mine'),
        )).name,
        'mine',
      );
    });

    test('archives and unarchives (UX-06)', () async {
      final archived = await service.update(
        'prj_1',
        mine.id,
        const UpdateWorkflowRequest(archived: true),
      );
      expect(archived.archivedAt, DateTime.utc(2026, 10, 13, 9));

      clock.advance(const Duration(hours: 1));
      final again = await service.update(
        'prj_1',
        mine.id,
        const UpdateWorkflowRequest(archived: true),
      );
      expect(again.archivedAt, archived.archivedAt, reason: 'first time kept');
      expect(
        (await service.list('prj_1'))
            .firstWhere((w) => w.id == mine.id)
            .archived,
        isTrue,
      );

      final back = await service.update(
        'prj_1',
        mine.id,
        const UpdateWorkflowRequest(archived: false),
      );
      expect(back.archivedAt, isNull);
    });

    test('catches a copy up with its built-in, and only a copy', () async {
      final copy = await service.create(
        'prj_1',
        name: 'my-dev',
        yaml: _simple,
        basedOn: const WorkflowBasedOn(builtin: 'dev-build', version: 1),
      );

      final caught = await service.update(
        'prj_1',
        copy.id,
        const UpdateWorkflowRequest(basedOnVersion: 2),
      );
      expect(
        caught.basedOn,
        const WorkflowBasedOn(builtin: 'dev-build', version: 2),
      );
      await expectLater(
        service.update(
          'prj_1',
          mine.id,
          const UpdateWorkflowRequest(basedOnVersion: 2),
        ),
        throwsA(isA<WorkflowEditException>()),
      );
    });

    test(
      'changes no built-in, and says nothing when nothing changes',
      () async {
        final builtin = (await service.list('prj_1'))
            .firstWhere((w) => w.builtin);
        await expectLater(
          service.update(
            'prj_1',
            builtin.id,
            const UpdateWorkflowRequest(archived: true),
          ),
          throwsA(isA<WorkflowBuiltinException>()),
        );

        final before = (await logged()).length;
        await service.update('prj_1', mine.id, const UpdateWorkflowRequest());
        expect(await logged(), hasLength(before));
      },
    );
  });

  group('save', () {
    test('adds a version and announces it', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );
      clock.advance(const Duration(minutes: 1));

      final saved = await service.save('prj_1', created.id, '$_simple# v2\n');

      expect(saved.version.version, 2);
      expect(saved.version.createdAt, DateTime.utc(2026, 10, 13, 9, 1));
      expect(saved.versions.length, 2);
      expect(
        (await logged()).last,
        isA<WorkflowSaved>().having((e) => e.version, 'version', 2),
      );
    });

    test('refuses a built-in', () async {
      final test = (await service.list('prj_1'))
          .firstWhere((w) => w.name == 'test');

      await expectLater(
        service.save('prj_1', test.id, _simple),
        throwsA(
          isA<WorkflowBuiltinException>().having((e) => e.name, 'name', 'test'),
        ),
      );
    });

    test('refuses a document with issues and keeps the old version', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );

      await expectLater(
        service.save('prj_1', created.id, 'nope'),
        throwsA(isA<WorkflowInvalidException>()),
      );
      expect((await service.get('prj_1', created.id)).version.version, 1);
    });

    test('needs a workflow', () async {
      await expectLater(
        service.save('prj_1', 'wf_nope', _simple),
        throwsA(isA<WorkflowNotFoundException>()),
      );
    });
  });

  group('remove', () {
    test('deletes a workflow of the owner and announces it', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );

      await service.remove('prj_1', created.id);

      await expectLater(
        service.get('prj_1', created.id),
        throwsA(isA<WorkflowNotFoundException>()),
      );
      expect(
        (await logged()).last,
        WorkflowRemoved(
          workflowId: created.id,
          projectId: 'prj_1',
          name: 'mine',
        ),
      );
    });

    test('keeps a built-in', () async {
      final test = (await service.list('prj_1'))
          .firstWhere((w) => w.name == 'test');

      await expectLater(
        service.remove('prj_1', test.id),
        throwsA(isA<WorkflowBuiltinException>()),
      );
    });

    test('keeps a workflow that jobs ran', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );
      repository.usedVersions.add(created.version.id);

      await expectLater(
        service.remove('prj_1', created.id),
        throwsA(isA<WorkflowInUseException>()),
      );
    });
  });

  group('schema', () {
    test('names the step types, gates, capabilities and axes', () {
      final schema = service.schema();

      expect(schema.schema, 1);
      expect(schema.steps.map((step) => step.kind), contains('build.android'));
      final command = schema.steps.firstWhere((step) => step.kind == 'command');
      expect(command.withKeys, [...command.withKeys]..sort());
      expect(schema.gates, contains('prod_release'));
      expect(schema.capabilities, contains('ios-sign'));
      expect(schema.capabilities, isNot(contains('ios-linux')));
      expect(schema.matrixAxes, ['platform', 'flavor']);
      expect(schema.platforms, ['android', 'ios']);
    });

    test('labels the gates and lists the variables (UX-02)', () {
      final schema = service.schema();

      expect(schema.gateLabels['prod_release'], 'Production release');
      expect(schema.gateLabels.keys, schema.gates);
      expect(
        schema.variables,
        containsAll([
          'app.name',
          'flavor.prod',
          'flavor.credentials.play_sa',
          'flavor.firebaseAppId.ios',
          'inputs',
          'platform',
        ]),
      );
      expect(schema.variables, [...schema.variables]..sort());
    });
  });

  group('templates', () {
    test('offers each template, valid as it is (UX-02)', () {
      final templates = service.templates();

      expect(templates.map((t) => t.id), [
        'blank',
        'android-firebase',
        'ios-testflight',
        'tests',
        'shorebird-patch',
      ]);
      for (final template in templates) {
        expect(template.title, isNotEmpty, reason: template.id);
        expect(template.description, isNotEmpty, reason: template.id);
        expect(
          service.validate(template.yaml).issues,
          isEmpty,
          reason: template.id,
        );
      }
    });
  });

  group('validate', () {
    test('says valid for a good document', () {
      final response = service.validate(_simple);

      expect(response.valid, isTrue);
      expect(response.issues, isEmpty);
    });

    test('lists the issues with their lines', () {
      final response = service.validate('schema: 1\nstages: []');

      expect(response.valid, isFalse);
      expect(response.issues.single.line, 2);
    });
  });

  group('latest and versionById', () {
    test('give what a dispatch and a job refer to', () async {
      final created = await service.create(
        'prj_1',
        name: 'mine',
        yaml: _simple,
      );
      await service.save('prj_1', created.id, '$_simple# v2\n');

      final latest = await service.latest('prj_1', created.id);
      final byId = await service.versionById(latest.version.id);

      expect(latest.workflow.name, 'mine');
      expect(latest.version.version, 2);
      expect(byId!.yaml, '$_simple# v2\n');
      expect(await service.versionById('wfv_nope'), isNull);
    });
  });

  group('the exceptions', () {
    test('print their messages', () {
      expect(const WorkflowException('m').toString(), 'WorkflowException: m');
      expect(
        const WorkflowNotFoundException('w').toString(),
        startsWith('WorkflowNotFoundException: '),
      );
      expect(
        const WorkflowExistsException('w').toString(),
        startsWith('WorkflowExistsException: '),
      );
      expect(
        const WorkflowBuiltinException('w').toString(),
        startsWith('WorkflowBuiltinException: '),
      );
      expect(
        const WorkflowInUseException('w').toString(),
        startsWith('WorkflowInUseException: '),
      );
      expect(
        const WorkflowArchivedException('w').toString(),
        'WorkflowArchivedException: The workflow "w" is archived. Unarchive '
        'it to run it.',
      );
      expect(
        const WorkflowNameException('w').toString(),
        startsWith('WorkflowNameException: '),
      );
      expect(
        WorkflowInvalidException(const []).toString(),
        startsWith('WorkflowInvalidException: The workflow has 0 issues'),
      );
      expect(
        WorkflowInvalidException(const [
          WorkflowIssue(
            line: 3,
            column: 5,
            message: 'The workflow has no input "notez".',
            hint: 'Did you mean "inputs.notes"?',
          ),
        ]).message,
        'The workflow has 1 issue: line 3, column 5: The workflow has no '
        'input "notez". Did you mean "inputs.notes"?',
      );
      expect(const DispatchException('m').toString(), 'DispatchException: m');
    });
  });
}
