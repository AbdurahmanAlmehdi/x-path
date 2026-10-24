import 'dart:async';
import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/mcp/mcp_tool.dart';
import 'package:xp/src/mcp/xp_tools.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late MockXpClient client;
  late Map<String, McpTool> tools;

  setUpAll(registerFallbacks);
  setUp(() {
    client = MockXpClient();
    tools = {
      for (final tool in buildXpTools(
        client,
        tailIdle: const Duration(milliseconds: 50),
      ))
        tool.name: tool,
    };
    when(() => client.listProjects()).thenAnswer((_) async => [sample.project]);
    when(() => client.listWorkflows('prj_1'))
        .thenAnswer((_) async => [sample.workflowSummary]);
  });

  Future<McpToolResult> call(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) => tools[name]!.handler(arguments);

  Object? decoded(McpToolResult result) => jsonDecode(result.text);

  /// The message of an error result, which is `{"code", "message", "hint"}`.
  String message(McpToolResult result) =>
      (decoded(result)! as Map<String, Object?>)['message']! as String;

  group('the tool list', () {
    test('has no way to approve, deny, loosen a gate, merge or delete', () {
      for (final name in tools.keys) {
        expect(name, isNot(contains('approve')), reason: name);
        expect(name, isNot(contains('deny')), reason: name);
        expect(name, isNot(contains('merge')), reason: name);
        expect(name, isNot(contains('abandon')), reason: name);
        expect(name, isNot(contains('remove')), reason: name);
        expect(name, isNot(contains('delete')), reason: name);
        expect(name, isNot(startsWith('set_')), reason: name);
        expect(name, isNot(startsWith('tighten')), reason: name);
      }
      expect(tools, contains('get_approval'));
      expect(tools, contains('get_gates'));
    });

    test('offers the tools of the plan', () {
      expect(
        tools.keys,
        containsAll([
          'list_projects',
          'get_project',
          'add_project',
          'update_project',
          'scan_project',
          'list_workflows',
          'get_workflow',
          'validate_workflow',
          'create_workflow',
          'update_workflow',
          'dispatch_workflow',
          'get_run',
          'get_job',
          'get_job_log_tail',
          'list_releases',
          'get_release',
          'list_approvals',
          'get_approval',
          'get_job_tests',
          'get_storage_report',
          'list_runners',
        ]),
      );
    });

    test('every tool has an object schema that lists only its properties', () {
      for (final tool in tools.values) {
        final schema = tool.inputSchema;
        final properties = (schema['properties']! as Map<String, Object?>).keys;
        expect(schema['type'], 'object', reason: tool.name);
        expect(
          properties,
          containsAll(schema['required']! as List<Object?>),
          reason: tool.name,
        );
        expect(tool.description, isNotEmpty, reason: tool.name);
      }
    });

    test('marks the tools that only read', () {
      expect(tools['list_projects']!.readOnly, isTrue);
      expect(tools['list_runners']!.readOnly, isTrue);
      expect(tools['get_approval']!.readOnly, isTrue);
      expect(tools['dispatch_workflow']!.readOnly, isFalse);
      expect(tools['create_workflow']!.readOnly, isFalse);
      expect(tools['add_project']!.readOnly, isFalse);
    });
  });

  group('runners', () {
    test('list_runners lists them with what they lack', () async {
      final runner = Runner(
        id: 'rnr_1',
        name: 'aws',
        status: RunnerStatus.online,
        capabilities: const ['flutter'],
        slots: 2,
        jobIds: const [],
        createdAt: DateTime.utc(2026, 10, 22),
        missing: const [
          MissingCapability(
            capability: 'android',
            reason: 'no JDK: java not found',
            fix: 'install JDK 17 or set JAVA_HOME',
          ),
        ],
      );
      when(() => client.listRunners()).thenAnswer((_) async => [runner]);

      final result = await call('list_runners');

      expect(result.isError, isFalse);
      final listed = (decoded(result)! as List).single as Map;
      expect(listed['name'], 'aws');
      expect((listed['missing'] as List).single, {
        'capability': 'android',
        'reason': 'no JDK: java not found',
        'fix': 'install JDK 17 or set JAVA_HOME',
      });
    });
  });

  group('projects', () {
    test('list_projects lists them', () async {
      final result = await call('list_projects');

      expect(result.isError, isFalse);
      expect(
        ((decoded(result)! as List).single as Map)['fullName'],
        'acme/app',
      );
    });

    test('get_project resolves a name', () async {
      when(() => client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);

      final result = await call('get_project', {'project': 'acme/app'});

      expect((decoded(result)! as Map)['id'], 'prj_1');
    });

    test('add_project adds a repository', () async {
      when(() => client.addProject(any()))
          .thenAnswer((_) async => sample.project);

      await call('add_project', {'remote': 'acme/app'});

      verify(
        () => client.addProject(const AddProjectRequest(remote: 'acme/app')),
      ).called(1);
    });

    test('add_project adds a folder', () async {
      when(() => client.addProject(any()))
          .thenAnswer((_) async => sample.project);

      await call('add_project', {'path': '/work/app'});

      verify(
        () => client.addProject(const AddProjectRequest(path: '/work/app')),
      ).called(1);
    });

    test('add_project wants exactly one of path and remote', () async {
      final neither = await call('add_project');
      final both = await call('add_project', {'path': '/a', 'remote': 'b/c'});

      expect(neither.isError, isTrue);
      expect(neither.text, contains('exactly one'));
      expect(both.isError, isTrue);
      verifyNever(() => client.addProject(any()));
    });

    test('scan_project scans', () async {
      when(() => client.scanProject('prj_1'))
          .thenAnswer((_) async => sample.project);

      final result = await call('scan_project', {'project': 'prj_1'});

      expect(result.isError, isFalse);
    });

    test('update_project applies edits', () async {
      when(() => client.updateProject('prj_1', any()))
          .thenAnswer((_) async => sample.project);

      await call('update_project', {
        'project': 'prj_1',
        'edits': {
          'defaultBaseBranch': 'develop',
          'apps': [
            {
              'path': '.',
              'flavors': [
                {'name': 'prod', 'prod': true},
              ],
            },
          ],
        },
      });

      final edits =
          verify(() => client.updateProject('prj_1', captureAny()))
                  .captured
                  .single
              as ProfileEdits;
      expect(edits.defaultBaseBranch, 'develop');
      expect(edits.apps.single.flavors.single.name, 'prod');
    });

    test('update_project says what is wrong with the edits', () async {
      final missing = await call('update_project', {'project': 'prj_1'});
      final broken = await call('update_project', {
        'project': 'prj_1',
        'edits': {'apps': 'nope'},
      });

      expect(missing.text, contains('"edits" is required'));
      expect(broken.isError, isTrue);
      expect(message(broken), startsWith('Invalid arguments'));
      expect((decoded(broken)! as Map)['code'], 'invalid_request');
    });
  });

  group('workflows', () {
    test('list_workflows lists them', () async {
      final result = await call('list_workflows', {'project': 'prj_1'});

      expect(((decoded(result)! as List).single as Map)['name'], 'dev-build');
    });

    test('get_workflow returns the YAML, at a version if asked', () async {
      when(() => client.getWorkflow('prj_1', 'wf_1', version: 2))
          .thenAnswer((_) async => sample.workflow);

      final result = await call('get_workflow', {
        'project': 'prj_1',
        'workflow': 'dev-build',
        'version': 2,
      });

      expect((decoded(result)! as Map)['yaml'], 'name: dev-build\n');
    });

    test('validate_workflow returns the issues with their lines', () async {
      when(() => client.validateWorkflow('prj_1', 'bad')).thenAnswer(
        (_) async => const ValidateWorkflowResponse(
          valid: false,
          issues: [WorkflowIssue(line: 4, column: 2, message: 'Unknown step.')],
        ),
      );

      final result = await call('validate_workflow', {
        'project': 'prj_1',
        'yaml': 'bad',
      });

      expect(result.isError, isFalse);
      expect(decoded(result), {
        'valid': false,
        'saved': false,
        'issues': [
          {'line': 4, 'column': 2, 'message': 'Unknown step.'},
        ],
      });
    });

    test('validate_workflow needs no project', () async {
      when(() => client.validateWorkflow(null, 'ok')).thenAnswer(
        (_) async => const ValidateWorkflowResponse(
          valid: false,
          issues: [
            WorkflowIssue(
              line: 4,
              column: 2,
              message: 'The workflow has no input "notez".',
              hint: 'Did you mean "inputs.notes"?',
            ),
          ],
        ),
      );

      final result = await call('validate_workflow', {'yaml': 'ok'});

      expect(decoded(result), {
        'valid': false,
        'saved': false,
        'issues': [
          {
            'line': 4,
            'column': 2,
            'message': 'The workflow has no input "notez".',
            'hint': 'Did you mean "inputs.notes"?',
          },
        ],
      });
    });

    test('a workflow_invalid error carries the issues', () async {
      when(() => client.validateWorkflow('prj_1', 'ok')).thenThrow(
        const ApiException(
          'The workflow has 1 issue.',
          statusCode: 422,
          code: ApiErrorCode.workflowInvalid,
          issues: [WorkflowIssue(line: 2, column: 1, message: 'Bad.')],
        ),
      );

      final result = await call('validate_workflow', {
        'project': 'prj_1',
        'yaml': 'ok',
      });

      expect(result.isError, isTrue);
      expect(decoded(result), {
        'code': 'workflow_invalid',
        'message': 'The workflow has 1 issue.',
        'hint': '',
        'issues': [
          {'line': 2, 'column': 1, 'message': 'Bad.'},
        ],
      });
    });

    group('create_workflow', () {
      test('saves a valid document', () async {
        when(
          () => client.validateWorkflow('prj_1', 'ok'),
        ).thenAnswer((_) async => const ValidateWorkflowResponse(valid: true));
        when(() => client.createWorkflow('prj_1', any()))
            .thenAnswer((_) async => sample.workflow);

        final result = await call('create_workflow', {
          'project': 'prj_1',
          'name': 'mine',
          'yaml': 'ok',
        });

        expect(result.isError, isFalse);
        verify(
          () => client.createWorkflow(
            'prj_1',
            const CreateWorkflowRequest(name: 'mine', yaml: 'ok'),
          ),
        ).called(1);
      });

      test('validates first and saves nothing when there are issues', () async {
        when(() => client.validateWorkflow('prj_1', 'bad')).thenAnswer(
          (_) async => const ValidateWorkflowResponse(
            valid: false,
            issues: [WorkflowIssue(line: 1, column: 1, message: 'No name.')],
          ),
        );

        final result = await call('create_workflow', {
          'project': 'prj_1',
          'name': 'mine',
          'yaml': 'bad',
        });

        expect(result.isError, isTrue);
        expect((decoded(result)! as Map)['issues'], [
          {'line': 1, 'column': 1, 'message': 'No name.'},
        ]);
        verifyNever(() => client.createWorkflow(any(), any()));
      });
    });

    group('update_workflow', () {
      test('saves a valid document as a new version', () async {
        when(
          () => client.validateWorkflow('prj_1', 'ok'),
        ).thenAnswer((_) async => const ValidateWorkflowResponse(valid: true));
        when(() => client.saveWorkflow('prj_1', 'wf_1', 'ok'))
            .thenAnswer((_) async => sample.workflow);

        final result = await call('update_workflow', {
          'project': 'prj_1',
          'workflow': 'dev-build',
          'yaml': 'ok',
        });

        expect(result.isError, isFalse);
      });

      test('validates first and saves nothing when there are issues', () async {
        when(() => client.validateWorkflow('prj_1', 'bad')).thenAnswer(
          (_) async => const ValidateWorkflowResponse(
            valid: false,
            issues: [WorkflowIssue(line: 9, column: 3, message: 'Bad.')],
          ),
        );

        final result = await call('update_workflow', {
          'project': 'prj_1',
          'workflow': 'wf_1',
          'yaml': 'bad',
        });

        expect(result.isError, isTrue);
        verifyNever(() => client.saveWorkflow(any(), any(), any()));
      });
    });
  });

  group('dispatch_workflow', () {
    test('runs a workflow and returns the run', () async {
      when(() => client.dispatchWorkflow('prj_1', 'wf_1', any())).thenAnswer(
        (_) async =>
            sample.run(state: RunState.queued, version: '1.2.3', build: 45),
      );

      final result = await call('dispatch_workflow', {
        'project': 'acme/app',
        'workflow': 'dev-build',
        'ref': 'main',
        'app': '.',
        'flavors': ['dev'],
        'platforms': ['android'],
        'bump': 'patch',
        'version': '1.2.4',
        'releaseVersion': '1.2.3+4',
        'inputs': {'notes': 'hi'},
      });

      final request =
          verify(() => client.dispatchWorkflow('prj_1', 'wf_1', captureAny()))
                  .captured
                  .single
              as DispatchRequest;
      expect(
        request,
        const DispatchRequest(
          ref: 'main',
          app: '.',
          flavors: ['dev'],
          platforms: ['android'],
          bump: VersionBump.patch,
          version: '1.2.4',
          releaseVersion: '1.2.3+4',
          inputs: {'notes': 'hi'},
        ),
      );
      final json = decoded(result)! as Map<String, dynamic>;
      expect((json['run'] as Map)['id'], 'run_1');
      expect(json['pendingApprovals'], isEmpty);
      expect(json, isNot(contains('note')));
    });

    test('defaults the optional arguments', () async {
      when(() => client.dispatchWorkflow('prj_1', 'wf_1', any()))
          .thenAnswer((_) async => sample.run());

      await call('dispatch_workflow', {'project': 'prj_1', 'workflow': 'wf_1'});

      verify(
        () => client.dispatchWorkflow('prj_1', 'wf_1', const DispatchRequest()),
      ).called(1);
    });

    test('plan_dispatch plans without dispatching', () async {
      const plan = DispatchPlan(flavors: ['dev'], platforms: ['android']);
      when(
        () => client.planDispatch(
          'prj_1',
          'wf_1',
          const DispatchRequest(flavors: ['dev']),
        ),
      ).thenAnswer((_) async => plan);

      final result = await call('plan_dispatch', {
        'project': 'prj_1',
        'workflow': 'wf_1',
        'flavors': ['dev'],
      });

      expect(result.isError, isFalse);
      expect(decoded(result), plan.toJson());
      expect(tools['plan_dispatch']!.readOnly, isTrue);
      verifyNever(() => client.dispatchWorkflow(any(), any(), any()));
    });

    test('refuses a bad argument without calling the engine', () async {
      final result = await call('dispatch_workflow', {
        'project': 'prj_1',
        'workflow': 'wf_1',
        'flavors': 'prod',
      });

      expect(result.isError, isTrue);
      expect(message(result), '"flavors" must be a list of strings.');
      verifyNever(() => client.dispatchWorkflow(any(), any(), any()));
    });

    test('shows a gated run as waiting, with the approval to poll', () async {
      when(
        () => client.dispatchWorkflow('prj_1', 'wf_1', any()),
      ).thenAnswer((_) async => sample.run(state: RunState.waitingForApproval));
      when(
        () => client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer((_) async => [sample.approval()]);

      final result = await call('dispatch_workflow', {
        'project': 'prj_1',
        'workflow': 'wf_1',
      });

      final json = decoded(result)! as Map<String, dynamic>;
      expect((json['run'] as Map)['state'], 'waiting_for_approval');
      expect(
        ((json['pendingApprovals'] as List<dynamic>).single as Map)['id'],
        'apr_1',
      );
      expect(json['note'], contains('Only the owner can approve'));
    });
  });

  group('runs and jobs', () {
    test('get_run lists the approvals a waiting run needs', () async {
      when(
        () => client.getRun('run_1'),
      ).thenAnswer((_) async => sample.run(state: RunState.waitingForApproval));
      when(
        () => client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer((_) async => [sample.approval()]);

      final result = await call('get_run', {'run': 'run_1'});

      expect(
        (decoded(result)! as Map)['pendingApprovals'] as List<dynamic>,
        hasLength(1),
      );
    });

    test('get_job shows the steps', () async {
      when(() => client.getJob('job_1')).thenAnswer((_) async => sample.job());

      final result = await call('get_job', {'job': 'job_1'});

      expect((decoded(result)! as Map)['steps'] as List<dynamic>, hasLength(1));
    });

    test('list_artifacts lists the files of a job', () async {
      when(() => client.listJobArtifacts('job_1'))
          .thenAnswer((_) async => [sample.artifact()]);

      final result = await call('list_artifacts', {'job': 'job_1'});

      expect(((decoded(result)! as List).single as Map)['name'], 'app.apk');
    });

    group('get_job_log_tail', () {
      LogLineFrame line(int seq) => LogLineFrame(
        seq: seq,
        step: 0,
        at: sample.at,
        stream: LogStream.stdout,
        text: 'line $seq',
      );

      test('returns the last lines of an ended job', () async {
        when(() => client.followJobLogs('job_1')).thenAnswer(
          (_) => Stream.fromIterable([
            line(1),
            line(2),
            line(3),
            const LogGapFrame(fromSeq: 4, toSeq: 4, count: 1),
            const LogEndFrame(state: JobState.failed),
          ]),
        );

        final result = await call('get_job_log_tail', {
          'job': 'job_1',
          'lines': 2,
        });

        expect(decoded(result), {
          'lines': ['line 2', 'line 3'],
          'jobEnded': true,
          'jobState': 'failed',
        });
      });

      test('returns what a running job has written so far', () async {
        final controller = StreamController<LogFrame>();
        addTearDown(controller.close);
        when(() => client.followJobLogs('job_1'))
            .thenAnswer((_) => controller.stream);
        controller.add(line(1));

        final result = await call('get_job_log_tail', {'job': 'job_1'});

        expect(decoded(result), {
          'lines': ['line 1'],
          'jobEnded': false,
        });
      });
    });

    test('get_job_tests passes the filters on', () async {
      when(
        () => client.getJobTests(
          'job_1',
          statuses: {TestStatus.failed},
          limit: 5,
          offset: 10,
        ),
      ).thenAnswer(
        (_) async => TestRunResponse(
          run: TestRun(
            id: 'tst_1',
            jobId: 'job_1',
            branch: 'main',
            appPath: '.',
            baseline: false,
            createdAt: sample.at,
            counts: const TestCounts(
              total: 1,
              passed: 0,
              failed: 1,
              errored: 0,
              skipped: 0,
            ),
            diff: const TestRunDiff(
              newFailures: [],
              fixed: [],
              missing: [],
              stillFailing: 1,
            ),
          ),
          total: 1,
          offset: 10,
          tests: const [],
        ),
      );

      final result = await call('get_job_tests', {
        'job': 'job_1',
        'statuses': ['failed'],
        'limit': 5,
        'offset': 10,
      });

      expect(result.isError, isFalse);
    });

    test('get_job_tests defaults to the failures', () async {
      when(() => client.getJobTests('job_1')).thenThrow(
        const ApiException(
          'No tests.',
          statusCode: 404,
          code: ApiErrorCode.notFound,
        ),
      );

      final result = await call('get_job_tests', {'job': 'job_1'});

      expect(decoded(result), {
        'code': 'not_found',
        'message': 'No tests.',
        'hint': '',
      });
    });

    test('get_job_tests refuses a status it does not know', () async {
      final result = await call('get_job_tests', {
        'job': 'job_1',
        'statuses': ['great'],
      });

      expect(message(result), 'Unknown status "great".');
    });

    test('get_test_baselines lists them', () async {
      when(() => client.getTestBaselines('prj_1')).thenAnswer(
        (_) async => [
          TestBaseline(
            appPath: '.',
            branch: 'main',
            jobId: 'job_0',
            createdAt: sample.at,
            counts: const TestCounts(
              total: 1,
              passed: 1,
              failed: 0,
              errored: 0,
              skipped: 0,
            ),
          ),
        ],
      );

      final result = await call('get_test_baselines', {'project': 'prj_1'});

      expect(decoded(result), hasLength(1));
    });
  });

  group('releases', () {
    test('list_releases passes the filters on', () async {
      when(
        () => client.listReleases(
          projectId: 'prj_1',
          app: '.',
          state: ReleaseState.live,
        ),
      ).thenAnswer((_) async => [sample.release()]);

      final result = await call('list_releases', {
        'project': 'acme/app',
        'app': '.',
        'state': 'live',
      });

      expect(decoded(result), hasLength(1));
    });

    test('list_releases without filters lists them all', () async {
      when(() => client.listReleases()).thenAnswer((_) async => []);

      final result = await call('list_releases');

      expect(decoded(result), isEmpty);
    });

    test('get_release and get_release_notes read', () async {
      when(() => client.getRelease('rel_1'))
          .thenAnswer((_) async => sample.release());
      when(() => client.getReleaseNotes('rel_1')).thenAnswer(
        (_) async => const ReleaseNotes(
          releaseId: 'rel_1',
          version: '1.2.3',
          build: 45,
          to: 'v1.2.3+45',
          commits: 0,
          groups: [],
          slack: 's',
          whatsapp: 'w',
        ),
      );

      expect(
        (decoded(await call('get_release', {'release': 'rel_1'}))!
            as Map)['id'],
        'rel_1',
      );
      expect(
        (decoded(await call('get_release_notes', {'release': 'rel_1'}))!
            as Map)['slack'],
        's',
      );
    });
  });

  group('approvals', () {
    test('get_approval polls by id', () async {
      when(() => client.getApproval('apr_1'))
          .thenAnswer((_) async => sample.approval());

      final result = await call('get_approval', {'approval': 'apr_1'});

      expect((decoded(result)! as Map)['state'], 'pending');
    });

    test('list_approvals filters by project, state and run', () async {
      when(
        () => client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer((_) async => [sample.approval()]);

      final mine = await call('list_approvals', {
        'project': 'prj_1',
        'state': 'pending',
        'run': 'run_1',
      });
      final other = await call('list_approvals', {
        'project': 'prj_1',
        'state': 'pending',
        'run': 'run_other',
      });

      expect(decoded(mine), hasLength(1));
      expect(decoded(other), isEmpty);
    });

    test('list_approvals without filters lists them all', () async {
      when(() => client.listApprovals()).thenAnswer((_) async => []);

      expect(decoded(await call('list_approvals')), isEmpty);
    });

    test('get_gates reads', () async {
      when(() => client.getGates('prj_1'))
          .thenAnswer((_) async => const ProjectGates({'push': true}));

      final result = await call('get_gates', {'project': 'prj_1'});

      expect(decoded(result), {
        'gates': {'push': true},
      });
    });
  });

  group('list_credentials', () {
    setUp(
      () => when(
        () => client.listNamedCredentials(),
      ).thenAnswer((_) async => [sample.ascCredential, sample.slackCredential]),
    );

    test('lists every credential with its assignments, no secret', () async {
      final result = await call('list_credentials');

      expect(result.isError, isFalse);
      final listed = decoded(result)! as List;
      expect(listed, hasLength(2));
      final asc = listed.first as Map;
      expect(asc['name'], 'Acme ASC');
      expect(asc['kind'], 'asc_key');
      expect(asc['status'], 'verified');
      expect(asc['account'], 'KEY123');
      expect(asc['usedBy'], [
        {
          'projectId': 'prj_1',
          'project': 'acme/app',
          'app': '.',
          'flavor': 'prod',
          'status': 'verified',
        },
        {
          'projectId': 'prj_2',
          'app': '.',
          'flavor': 'default',
          'status': 'rejected',
          'message': 'The key cannot see com.acme.other.',
          'fix': 'Give the key access to the app.',
        },
      ]);
      for (final secret in [
        'password',
        'privateKey',
        'token',
        'webhookUrl',
        'serviceAccount',
        'storePassword',
      ]) {
        expect(result.text, isNot(contains(secret)));
      }
    });

    test('with a project keeps its credentials and its flavors', () async {
      final result = await call('list_credentials', {'project': 'acme/app'});

      final listed = decoded(result)! as List;
      expect(listed, hasLength(1));
      final asc = listed.single as Map;
      expect(asc['id'], 'crd_1');
      expect((asc['usedBy'] as List).single, containsPair('flavor', 'prod'));
    });

    test('is read-only, and there is no tool that changes one', () {
      expect(tools['list_credentials']!.readOnly, isTrue);
      expect(
        tools.keys.where(
          (name) => name.contains('credential') && name != 'list_credentials',
        ),
        isEmpty,
      );
    });
  });

  test('get_storage_report reads', () async {
    when(() => client.getStorage())
        .thenAnswer((_) async => sample.storageReport());

    expect((await call('get_storage_report')).isError, isFalse);
  });

  group('failures', () {
    test(
      'the engine refusing the token kind says what the token may do',
      () async {
        when(() => client.listProjects()).thenThrow(
          const ApiException(
            'An mcp token cannot do that.',
            statusCode: 403,
            code: ApiErrorCode.forbidden,
          ),
        );

        final result = await call('list_projects');

        expect(result.isError, isTrue);
        expect(result.text, contains('can never approve or loosen a gate'));
      },
    );

    test('a rejected token says how to save a new one', () async {
      when(() => client.listProjects()).thenThrow(
        const ApiException(
          'Bad.',
          statusCode: 401,
          code: ApiErrorCode.unauthorized,
        ),
      );

      final result = await call('list_projects');

      expect(result.text, contains('xp connect --mcp-token'));
    });

    test('another engine error passes its message on', () async {
      when(() => client.listProjects()).thenThrow(
        const ApiException(
          'Busy.',
          statusCode: 503,
          code: ApiErrorCode.secretsLocked,
        ),
      );

      final result = await call('list_projects');
      expect(message(result), 'Busy.');
      expect((decoded(result)! as Map)['code'], 'secrets_locked');
    });

    test('an engine that cannot be reached', () async {
      when(() => client.listProjects())
          .thenThrow(const ConnectionException('Cannot reach the engine.'));

      final result = await call('list_projects');

      expect(result.isError, isTrue);
      expect(decoded(result), {
        'code': 'unreachable',
        'message': 'Cannot reach the engine.',
        'hint': '',
      });
    });

    test('a project that does not exist', () async {
      when(() => client.listProjects()).thenAnswer((_) async => []);

      final result = await call('get_project', {'project': 'ghost'});

      expect(result.isError, isTrue);
      expect(decoded(result), {
        'code': 'not_found',
        'message': 'No project "ghost".',
        'hint': 'See: list_projects',
      });
    });

    test('a name that is more than one project names no tool', () async {
      when(() => client.listProjects())
          .thenAnswer((_) async => [sample.project, sample.project]);

      final result = await call('get_project', {'project': 'app'});

      expect((decoded(result)! as Map)['code'], 'ambiguous');
      expect((decoded(result)! as Map)['hint'], '');
    });

    test('an error that is not about the arguments says what it was', () async {
      when(() => client.listProjects()).thenThrow(const _Broken());

      final result = await call('list_projects');

      expect(decoded(result), {
        'code': 'internal',
        'message': 'Broken.',
        'hint': '',
      });
    });

    test('a value that does not parse is an argument error', () async {
      when(() => client.listProjects()).thenThrow(const FormatException('x'));

      final result = await call('list_projects');

      expect(message(result), 'Invalid arguments: x');
    });

    test('an argument error reads as its message', () {
      expect(const McpArgumentError('Wrong.').toString(), 'Wrong.');
    });

    test('a missing or mistyped argument', () async {
      expect(message(await call('get_job')), '"job" is required.');
      expect(
        message(await call('get_job', {'job': 3})),
        '"job" must be a string.',
      );
      expect(
        message(await call('get_job_log_tail', {'job': 'j', 'lines': 'x'})),
        '"lines" must be an integer.',
      );
      expect(
        message(await call('update_project', {'project': 'p', 'edits': 'x'})),
        '"edits" must be an object.',
      );
    });
  });
}

class _Broken implements Exception {
  const new();

  @override
  String toString() => 'Broken.';
}
