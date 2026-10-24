import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;
  late Directory directory;
  late File document;

  setUpAll(registerFallbacks);
  setUp(() {
    env = TestEnv();
    directory = Directory.systemTemp.createTempSync('xp_workflows');
    document = File('${directory.path}/wf.yaml')
      ..writeAsStringSync('name: dev-build\n');
    when(() => env.client.listWorkflows('prj_1'))
        .thenAnswer((_) async => [sample.workflowSummary]);
  });
  tearDown(() {
    env.dispose();
    directory.deleteSync(recursive: true);
  });

  test('list prints the workflows', () async {
    await env.runOk(['workflows', 'list', 'prj_1']);

    expect(env.logger.out, contains('wf_1'));
    expect(env.logger.out, contains('dev-build'));
    expect(env.logger.out, contains('yes'));
  });

  test('list with --json prints them as JSON', () async {
    await env.runOk(['--json', 'workflows', 'list', 'prj_1']);

    expect(
      (jsonDecode(env.logger.infos.single) as List<dynamic>).single,
      isA<Map<String, dynamic>>(),
    );
  });

  group('show', () {
    test('prints the YAML of the newest version', () async {
      when(() => env.client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['workflows', 'show', 'prj_1', 'dev-build']);

      expect(env.logger.infos, ['name: dev-build']);
    });

    test('prints the YAML of a version', () async {
      when(() => env.client.getWorkflow('prj_1', 'wf_1', version: 3))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['workflows', 'show', 'prj_1', 'wf_1', '--version', '3']);

      verify(() => env.client.getWorkflow('prj_1', 'wf_1', version: 3))
          .called(1);
    });

    test('refuses a version that is not a number', () async {
      expect(
        await env.run(['workflows', 'show', 'prj_1', 'wf_1', '--version', 'x']),
        64,
      );
    });

    test('with --json prints the workflow', () async {
      when(() => env.client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['--json', 'workflows', 'show', 'prj_1', 'wf_1']);

      expect((jsonDecode(env.logger.infos.single) as Map)['yaml'], isNotNull);
    });
  });

  group('schema', () {
    const schema = WorkflowSchema(
      schema: 1,
      steps: [
        StepType(
          kind: 'build.ios',
          title: 'Build iOS',
          description: 'Builds and signs an IPA.',
          group: 'Build',
          capabilities: [
            ['ios-sign', 'flutter'],
          ],
          keys: [
            StepKeySchema(
              name: 'exportOptionsPlist',
              type: StepKeyType.string,
              required: true,
              description: 'The export options plist.',
            ),
            StepKeySchema(
              name: 'obfuscate',
              type: StepKeyType.boolean,
              defaultValue: false,
              description: 'Obfuscate.',
            ),
          ],
        ),
        StepType(kind: 'version.bump', title: 'Bump', group: 'Source'),
        StepType(kind: 'x'),
      ],
      gates: ['push', 'merge'],
      gateLabels: {'push': 'Push'},
      capabilities: [],
      matrixAxes: [],
      platforms: [],
      variables: ['flavor', 'platform'],
    );

    setUp(() {
      when(env.client.getWorkflowSchema).thenAnswer((_) async => schema);
    });

    test('lists the step types by group, the gates and variables', () async {
      await env.runOk(['workflows', 'schema']);

      final out = env.logger.out;
      expect(out, contains('Build\n  build.ios'));
      expect(out, contains('Build iOS'));
      expect(out, contains('Source\n  version.bump'));
      expect(out, contains('Other\n  x'));
      expect(out, contains('  push  Push\n  merge'));
      expect(out, contains('Variables\n  flavor, platform'));
    });

    test('shows one step type with its keys', () async {
      await env.runOk(['workflows', 'schema', '--kind', 'build.ios']);

      final out = env.logger.out;
      expect(out, startsWith('build.ios: Build iOS\nBuilds and signs an IPA.'));
      expect(out, contains('Needs ios-sign and flutter.'));
      expect(out, contains('string, required'));
      expect(out, contains('boolean, default false'));

      env.logger.infos.clear();
      await env.runOk(['workflows', 'schema', '--kind', 'version.bump']);
      expect(env.logger.out, contains('It takes nothing under "with".'));
    });

    test('prints JSON', () async {
      await env.runOk(['workflows', 'schema', '--kind', 'x', '--json']);

      expect(jsonDecode(env.logger.out), const StepType(kind: 'x').toJson());
    });

    test('says when there is no such step type', () async {
      expect(await env.run(['workflows', 'schema', '--kind', 'nope']), 64);
      expect(env.logger.errors.single, contains('No step type "nope"'));
    });
  });

  group('validate', () {
    test('says a document is valid, without a project', () async {
      when(() => env.client.validateWorkflow(null, 'name: dev-build\n'))
          .thenAnswer((_) async => const ValidateWorkflowResponse(valid: true));

      await env.runOk(['workflows', 'validate', document.path]);

      expect(env.logger.out, 'The workflow is valid.');
    });

    test('still takes a project and --file', () async {
      when(() => env.client.validateWorkflow(null, 'name: dev-build\n'))
          .thenAnswer((_) async => const ValidateWorkflowResponse(valid: true));

      await env.runOk([
        'workflows',
        'validate',
        'prj_1',
        '--file',
        document.path,
      ]);

      expect(env.logger.out, 'The workflow is valid.');
    });

    test('lists the issues one per line with hints and exits 65', () async {
      when(() => env.client.validateWorkflow(null, 'name: dev-build\n'))
          .thenAnswer(
            (_) async => const ValidateWorkflowResponse(
              valid: false,
              issues: [
                WorkflowIssue(
                  line: 3,
                  column: 5,
                  message: 'Unknown step type "build.andriod".',
                  hint: 'Did you mean "build.android"?',
                ),
                WorkflowIssue(line: 9, column: 1, message: 'No jobs.'),
              ],
            ),
          );

      final code = await env.run([
        'workflows',
        'validate',
        '-f',
        document.path,
      ]);

      expect(code, 65);
      expect(
        env.logger.out,
        contains(
          '  3:5: Unknown step type "build.andriod". Did you mean '
          '"build.android"?',
        ),
      );
      expect(env.logger.out, contains('  9:1: No jobs.'));
    });

    test('without a file is a usage error', () async {
      expect(await env.run(['workflows', 'validate']), 64);
      expect(env.logger.errors.single, contains('<file>'));
    });

    test('with a file that does not exist is a usage error', () async {
      expect(
        await env.run([
          'workflows',
          'validate',
          '${directory.path}/missing.yaml',
        ]),
        64,
      );
    });
  });

  test('create prints the issues of a document one per line', () async {
    when(() => env.client.createWorkflow('prj_1', any())).thenThrow(
      const ApiException(
        'The workflow has 2 issues: ...',
        statusCode: 422,
        code: ApiErrorCode.workflowInvalid,
        issues: [
          WorkflowIssue(
            line: 4,
            column: 9,
            message: 'The workflow has no input "notez".',
            hint: 'Did you mean "inputs.notes"?',
          ),
          WorkflowIssue(line: 7, column: 3, message: 'No jobs.'),
        ],
      ),
    );

    final code = await env.run([
      'workflows',
      'create',
      'prj_1',
      'my-flow',
      '--file',
      document.path,
    ]);

    expect(code, isNot(0));
    expect(
      env.logger.errors.single,
      'The workflow has issues:\n'
      '  4:9: The workflow has no input "notez". Did you mean '
      '"inputs.notes"?\n'
      '  7:3: No jobs.',
    );
  });

  test('create without --file is a usage error', () async {
    expect(await env.run(['workflows', 'create', 'prj_1', 'dev']), 64);
    expect(env.logger.errors.single, contains('--file is required.'));
  });

  test('create saves a file as a new workflow', () async {
    when(() => env.client.createWorkflow('prj_1', any()))
        .thenAnswer((_) async => sample.workflow);

    await env.runOk([
      'workflows',
      'create',
      'prj_1',
      'my-flow',
      '--file',
      document.path,
    ]);

    final request =
        verify(() => env.client.createWorkflow('prj_1', captureAny()))
                .captured
                .single
            as CreateWorkflowRequest;
    expect(request.name, 'my-flow');
    expect(request.yaml, 'name: dev-build\n');
    expect(env.logger.out, 'Created dev-build (wf_1), version 2.');
  });

  group('edit', () {
    test('saves a file as a new version', () async {
      when(() => env.client.saveWorkflow('prj_1', 'wf_1', 'name: dev-build\n'))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk([
        'workflows',
        'edit',
        'prj_1',
        'dev-build',
        '--file',
        document.path,
      ]);

      expect(env.logger.out, 'Saved version 2 of dev-build.');
    });

    test('shows why the engine refused a document', () async {
      when(() => env.client.saveWorkflow('prj_1', 'wf_1', any())).thenThrow(
        const ApiException(
          'Line 2: unknown key.',
          statusCode: 422,
          code: ApiErrorCode.workflowInvalid,
        ),
      );

      final code = await env.run([
        'workflows',
        'edit',
        'prj_1',
        'dev-build',
        '--file',
        document.path,
      ]);

      expect(code, 65);
      expect(env.logger.errors.single, 'Line 2: unknown key.');
    });
  });

  group('lifecycle (UX-06)', () {
    Workflow builtin() => Workflow(
      id: 'wf_1',
      projectId: 'prj_1',
      name: 'dev-build',
      builtin: true,
      version: sample.workflow.version,
      versions: sample.workflow.versions,
      yaml: 'name: dev-build\n',
    );

    test('copy saves a built-in as a workflow that remembers it', () async {
      when(() => env.client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => builtin());
      when(() => env.client.createWorkflow('prj_1', any()))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['workflows', 'copy', 'prj_1', 'dev-build', 'mine']);

      final request =
          verify(() => env.client.createWorkflow('prj_1', captureAny()))
                  .captured
                  .single
              as CreateWorkflowRequest;
      expect(request.name, 'mine');
      expect(request.yaml, 'name: dev-build\n');
      expect(
        request.basedOn,
        WorkflowBasedOn(
          builtin: 'dev-build',
          version: sample.workflow.version.version,
        ),
      );
      expect(env.logger.out, 'Copied dev-build to dev-build (wf_1).');
    });

    test('copy of a copy keeps what it is based on', () async {
      when(() => env.client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => sample.workflow);
      when(() => env.client.createWorkflow('prj_1', any()))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['workflows', 'copy', 'prj_1', 'wf_1', 'mine']);

      final request =
          verify(() => env.client.createWorkflow('prj_1', captureAny()))
                  .captured
                  .single
              as CreateWorkflowRequest;
      expect(request.basedOn, isNull);
    });

    test('rename, archive and unarchive', () async {
      when(() => env.client.updateWorkflow('prj_1', 'wf_1', any()))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['workflows', 'rename', 'prj_1', 'wf_1', 'nightly']);
      await env.runOk(['workflows', 'archive', 'prj_1', 'wf_1']);
      await env.runOk(['workflows', 'archive', 'prj_1', 'wf_1', '--undo']);

      expect(
        verify(() => env.client.updateWorkflow('prj_1', 'wf_1', captureAny()))
            .captured,
        const [
          UpdateWorkflowRequest(name: 'nightly'),
          UpdateWorkflowRequest(archived: true),
          UpdateWorkflowRequest(archived: false),
        ],
      );
      const archived =
          'Archived dev-build. Undo with: xp workflows archive prj_1 '
          'dev-build --undo';
      expect(env.logger.infos, [
        'Renamed to dev-build.',
        archived,
        'Unarchived dev-build.',
      ]);
    });

    test('delete, and archive instead of one that ran', () async {
      when(() => env.client.deleteWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async {});

      await env.runOk(['workflows', 'delete', 'prj_1', 'wf_1']);
      expect(env.logger.out, 'Deleted wf_1.');

      when(() => env.client.deleteWorkflow('prj_1', 'wf_1')).thenThrow(
        const ApiException(
          'Workflow wf_1 has been run, and the jobs keep the version they '
          'ran, so it cannot be deleted.',
          statusCode: 409,
          code: ApiErrorCode.conflict,
        ),
      );
      expect(await env.run(['workflows', 'delete', 'prj_1', 'wf_1']), 73);
      expect(
        env.logger.errors.single,
        endsWith(
          'Archive it instead: xp workflows archive <project> <workflow>',
        ),
      );
    });

    test('versions lists them, oldest first', () async {
      when(() => env.client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => sample.workflow);

      await env.runOk(['workflows', 'versions', 'prj_1', 'wf_1']);

      expect(env.logger.out, startsWith('VERSION'));
      expect(env.logger.out, contains(sample.workflow.version.id));
    });

    group('diff', () {
      Workflow at(int version, String yaml) => Workflow(
        id: 'wf_1',
        projectId: 'prj_1',
        name: 'mine',
        builtin: false,
        version: WorkflowVersionInfo(
          id: 'wfv_$version',
          version: version,
          createdAt: DateTime.utc(2026),
        ),
        versions: const [],
        yaml: yaml,
      );

      test('prints what changed between two versions', () async {
        when(() => env.client.getWorkflow('prj_1', 'wf_1', version: 1))
            .thenAnswer((_) async => at(1, 'a\nb\n'));
        when(() => env.client.getWorkflow('prj_1', 'wf_1'))
            .thenAnswer((_) async => at(3, 'a\nc\n'));

        await env.runOk(['workflows', 'diff', 'prj_1', 'wf_1', '1']);

        expect(
          env.logger.out,
          '--- version 1\n+++ version 3\n@@ -1,2 +1,2 @@\n a\n-b\n+c',
        );
      });

      test('says when two versions are the same', () async {
        when(() => env.client.getWorkflow('prj_1', 'wf_1', version: 1))
            .thenAnswer((_) async => at(1, 'a\n'));
        when(() => env.client.getWorkflow('prj_1', 'wf_1', version: 2))
            .thenAnswer((_) async => at(2, 'a\n'));

        await env.runOk(['workflows', 'diff', 'prj_1', 'wf_1', '1', '2']);

        expect(env.logger.out, 'Versions 1 and 2 are the same.');
      });

      test('needs a version number', () async {
        expect(await env.run(['workflows', 'diff', 'prj_1', 'wf_1']), 64);
        expect(
          await env.run(['workflows', 'diff', 'prj_1', 'wf_1', 'one']),
          64,
        );
      });
    });
  });
}
