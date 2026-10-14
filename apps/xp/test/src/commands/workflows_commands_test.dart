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

  group('validate', () {
    test('says a document is valid', () async {
      when(() => env.client.validateWorkflow('prj_1', 'name: dev-build\n'))
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

    test('lists the issues with their lines and exits 65', () async {
      when(() => env.client.validateWorkflow('prj_1', any())).thenAnswer(
        (_) async => const ValidateWorkflowResponse(
          valid: false,
          issues: [
            WorkflowIssue(line: 3, column: 5, message: 'Unknown step.'),
            WorkflowIssue(line: 9, column: 1, message: 'No jobs.'),
          ],
        ),
      );

      final code = await env.run([
        'workflows',
        'validate',
        'prj_1',
        '-f',
        document.path,
      ]);

      expect(code, 65);
      expect(env.logger.out, contains('  3:5: Unknown step.'));
      expect(env.logger.out, contains('  9:1: No jobs.'));
    });

    test('without --file is a usage error', () async {
      expect(await env.run(['workflows', 'validate', 'prj_1']), 64);
      expect(env.logger.errors.single, contains('--file'));
    });

    test('with a file that does not exist is a usage error', () async {
      expect(
        await env.run([
          'workflows',
          'validate',
          'prj_1',
          '--file',
          '${directory.path}/missing.yaml',
        ]),
        64,
      );
    });
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
}
