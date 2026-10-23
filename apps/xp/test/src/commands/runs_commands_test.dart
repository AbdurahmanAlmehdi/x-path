import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/commands/runs_commands.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUpAll(registerFallbacks);
  setUp(() {
    env = TestEnv();
    when(() => env.client.listWorkflows('prj_1'))
        .thenAnswer((_) async => [sample.workflowSummary]);
  });
  tearDown(() => env.dispose());

  group('dispatch', () {
    setUp(() {
      when(() => env.client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => sample.workflow);
      when(() => env.client.dispatchWorkflow('prj_1', 'wf_1', any()))
          .thenAnswer(
            (_) async =>
                sample.run(state: RunState.queued, version: '1.2.3', build: 45),
          );
    });

    DispatchRequest sent() =>
        verify(() => env.client.dispatchWorkflow('prj_1', 'wf_1', captureAny()))
                .captured
                .single
            as DispatchRequest;

    test('runs a workflow with the defaults', () async {
      await env.runOk(['dispatch', 'prj_1', 'dev-build']);

      expect(sent(), const DispatchRequest());
      expect(env.logger.out, contains('Dispatched run_1.'));
      expect(env.logger.out, contains('run_1  queued  1.2.3+45'));
      expect(env.logger.out, contains('job_1  prepare'));
    });

    test('passes every option on', () async {
      await env.runOk([
        'dispatch',
        'prj_1',
        'wf_1',
        '--ref',
        'develop',
        '--app',
        'apps/a',
        '--flavor',
        'prod',
        '--flavor',
        'dev',
        '--platform',
        'ios',
        '--bump',
        'minor',
        '--version',
        '2.0.0',
        '--release-version',
        '1.9.0+3',
        '--input',
        'notes=hello',
        '--input',
        'count=3',
        '--input',
        'testerGroups=["a","b"]',
        '--input',
        'empty=',
      ]);

      expect(
        sent(),
        const DispatchRequest(
          ref: 'develop',
          app: 'apps/a',
          flavors: ['prod', 'dev'],
          platforms: ['ios'],
          bump: VersionBump.minor,
          version: '2.0.0',
          releaseVersion: '1.9.0+3',
          inputs: {
            'notes': 'hello',
            'count': 3,
            'testerGroups': ['a', 'b'],
            'empty': '',
          },
        ),
      );
    });

    group('with typed inputs (UX-04)', () {
      setUp(() {
        when(() => env.client.getWorkflow('prj_1', 'wf_1')).thenAnswer(
          (_) async => Workflow(
            id: 'wf_1',
            projectId: 'prj_1',
            name: 'dev-build',
            builtin: false,
            version: sample.workflowVersion,
            versions: [sample.workflowVersion],
            yaml: 'name: dev-build\n',
            inputs: const [
              WorkflowInput(name: 'notes', type: InputType.string),
              WorkflowInput(name: 'ids', type: InputType.json),
              WorkflowInput(name: 'flag', type: InputType.boolean),
              WorkflowInput(
                name: 'track',
                type: InputType.choice,
                options: ['internal', 'beta'],
              ),
              WorkflowInput(
                name: 'release',
                type: InputType.release,
                description: 'The release.',
                required: true,
              ),
            ],
          ),
        );
      });

      test('reads each input as its type', () async {
        await env.runOk([
          'dispatch',
          'prj_1',
          'wf_1',
          '--input',
          'notes=true',
          '--input',
          'ids={"dev": 1}',
          '--input',
          'flag=TRUE',
          '--input',
          'track=beta',
          '--input',
          'release=1.2.0+3',
        ]);

        expect(sent().inputs, {
          'notes': 'true',
          'ids': {'dev': 1},
          'flag': true,
          'track': 'beta',
          'release': '1.2.0+3',
        });
      });

      test('refuses a value that is not its type', () async {
        expect(
          await env.run(['dispatch', 'prj_1', 'wf_1', '--input', 'flag=yes']),
          64,
        );
        expect(
          env.logger.errors.first,
          'The input "flag" is true or false, not "yes".',
        );
        expect(
          await env.run(['dispatch', 'prj_1', 'wf_1', '--input', 'ids={']),
          64,
        );
        verifyNever(() => env.client.dispatchWorkflow(any(), any(), any()));
      });

      test('asks for a required input on a terminal', () async {
        env.prompt
          ..interactive = true
          ..answers.add('1.2.0+3');

        await env.runOk(['dispatch', 'prj_1', 'wf_1']);

        expect(env.prompt.questions, ['release — The release.']);
        expect(sent().inputs, {'release': '1.2.0+3'});
      });

      test('reads an input file, under what --input gives', () async {
        final file = File('${env.directory.path}/inputs.yaml')
          ..writeAsStringSync(
            'notes: From the file\nids:\n  dev: [1, 2]\nrelease: 1.2.0+3\n',
          );

        await env.runOk([
          'dispatch',
          'prj_1',
          'wf_1',
          '--input-file',
          file.path,
          '--input',
          'notes=From the flag',
        ]);

        expect(sent().inputs, {
          'notes': 'From the flag',
          'ids': {
            'dev': [1, 2],
          },
          'release': '1.2.0+3',
        });
      });

      test('says what is wrong with an input file', () async {
        final directory = env.directory.path;
        File('$directory/list.json').writeAsStringSync('[1]');
        File('$directory/broken.yaml').writeAsStringSync('a: [');

        expect(
          await env.run([
            'dispatch',
            'prj_1',
            'wf_1',
            '--input-file',
            '$directory/none.yaml',
          ]),
          66,
        );
        expect(
          await env.run([
            'dispatch',
            'prj_1',
            'wf_1',
            '--input-file',
            '$directory/list.json',
          ]),
          64,
        );
        expect(
          await env.run([
            'dispatch',
            'prj_1',
            'wf_1',
            '--input-file',
            '$directory/broken.yaml',
          ]),
          64,
        );
      });
    });

    test('refuses an input without a key', () async {
      expect(await env.run(['dispatch', 'prj_1', 'wf_1', '--input', '=x']), 64);
      expect(
        await env.run(['dispatch', 'prj_1', 'wf_1', '--input', 'novalue']),
        64,
      );
    });

    test('refuses a bump it does not know', () async {
      expect(
        await env.run(['dispatch', 'prj_1', 'wf_1', '--bump', 'huge']),
        64,
      );
    });

    test('prints the run as JSON', () async {
      await env.runOk(['--json', 'dispatch', 'prj_1', 'wf_1']);

      expect((jsonDecode(env.logger.infos.single) as Map)['id'], 'run_1');
    });

    test('says why the engine refused', () async {
      when(() => env.client.dispatchWorkflow('prj_1', 'wf_1', any())).thenThrow(
        const ApiException(
          'The project has no flavor "x".',
          statusCode: 422,
          code: ApiErrorCode.workflowInvalid,
        ),
      );

      expect(await env.run(['dispatch', 'prj_1', 'wf_1']), 65);
    });
  });

  group('runs', () {
    test('show lists the jobs', () async {
      when(() => env.client.getRun('run_1'))
          .thenAnswer((_) async => sample.run());

      await env.runOk(['runs', 'show', 'run_1']);

      expect(env.logger.out, contains('run_1  running'));
      expect(env.logger.out, contains('sha: ${'a' * 40}'));
      verifyNever(
        () => env.client.listApprovals(
          projectId: any(named: 'projectId'),
          state: any(named: 'state'),
        ),
      );
    });

    test('show names the approval a waiting run needs', () async {
      when(
        () => env.client.getRun('run_1'),
      ).thenAnswer((_) async => sample.run(state: RunState.waitingForApproval));
      when(
        () => env.client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer(
        (_) async => [
          sample.approval(),
          Approval(
            id: 'apr_other',
            projectId: 'prj_1',
            action: 'merge',
            sha: 'c' * 40,
            runId: 'run_other',
            state: ApprovalState.pending,
            createdAt: sample.at,
            expiresAt: sample.at,
          ),
        ],
      );

      await env.runOk(['runs', 'show', 'run_1']);

      expect(
        env.logger.out,
        contains('Waiting for approval apr_1 (prod_release)'),
      );
      expect(env.logger.out, contains('xp approvals approve apr_1'));
      expect(env.logger.out, isNot(contains('apr_other')));
    });

    test('show with --json adds the pending approvals', () async {
      when(
        () => env.client.getRun('run_1'),
      ).thenAnswer((_) async => sample.run(state: RunState.waitingForApproval));
      when(
        () => env.client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer((_) async => [sample.approval()]);

      await env.runOk(['--json', 'runs', 'show', 'run_1']);

      final json = jsonDecode(env.logger.infos.single) as Map<String, dynamic>;
      expect(((json['pendingApprovals'] as List).single as Map)['id'], 'apr_1');
    });

    test(
      'show with --json leaves out the approvals when there are none',
      () async {
        when(() => env.client.getRun('run_1'))
            .thenAnswer((_) async => sample.run());

        await env.runOk(['--json', 'runs', 'show', 'run_1']);

        expect(
          jsonDecode(env.logger.infos.single),
          isNot(contains('pendingApprovals')),
        );
      },
    );

    test('cancel cancels', () async {
      when(() => env.client.cancelRun('run_1'))
          .thenAnswer((_) async => sample.run(state: RunState.cancelled));

      await env.runOk(['runs', 'cancel', 'run_1']);

      expect(env.logger.out, contains('run_1  cancelled'));
    });
  });

  group('jobs', () {
    test('show lists the steps', () async {
      when(() => env.client.getJob('job_1'))
          .thenAnswer((_) async => sample.job(state: JobState.failed));

      await env.runOk(['jobs', 'show', 'job_1']);

      expect(env.logger.out, contains('job_1  failed  prepare'));
      expect(env.logger.out, contains('message: It broke'));
      expect(env.logger.out, contains('guard'));
    });

    test('show says why each step failed and what the guards say to fix', () {
      final job = Job(
        id: 'job_1',
        projectId: 'prj_1',
        workflowVersionId: 'wfv_1',
        state: JobState.failed,
        createdAt: sample.at,
        steps: const [
          JobStep(
            ordinal: 0,
            kind: 'guard',
            state: StepState.succeeded,
            sideEffect: false,
            attempts: 1,
            result: {
              'results': [
                {'name': 'credentials', 'status': 'passed', 'message': 'ok'},
                {
                  'name': 'versionSync',
                  'status': 'warning',
                  'message': 'The iOS version differs.',
                  'fix': 'Run flutter pub get.',
                },
              ],
            },
          ),
          JobStep(
            ordinal: 1,
            kind: 'build.ios',
            state: StepState.failed,
            sideEffect: false,
            attempts: 1,
            message: 'xcodebuild exited with 65.\nSee the log.',
          ),
          JobStep(
            ordinal: 2,
            kind: 'gate',
            state: StepState.waitingForApproval,
            sideEffect: false,
            attempts: 1,
          ),
          JobStep(
            ordinal: 3,
            kind: 'guard',
            state: StepState.pending,
            sideEffect: false,
            attempts: 0,
            result: {'results': 'none'},
          ),
        ],
      );

      final text = describeJob(job);

      expect(
        text,
        contains(
          'step 1 (build.ios) failed:\n'
          '  xcodebuild exited with 65.\n'
          '  See the log.',
        ),
      );
      expect(text, contains('fix (guard versionSync): Run flutter pub get.'));
      expect(text, isNot(contains('fix (guard credentials)')));
      expect(text, contains('waiting_for_approval'));
    });

    test('show copes with a job that has no name', () async {
      when(() => env.client.getJob('job_1'))
          .thenAnswer((_) async => sample.job(name: null));

      await env.runOk(['jobs', 'show', 'job_1']);

      expect(env.logger.out, startsWith('job_1  running\n'));
    });

    test('cancel cancels', () async {
      when(() => env.client.cancelJob('job_1'))
          .thenAnswer((_) async => sample.job(state: JobState.cancelled));

      await env.runOk(['jobs', 'cancel', 'job_1']);

      expect(env.logger.out, contains('cancelled'));
    });

    test('resume goes on at the first unfinished step', () async {
      when(() => env.client.resumeJob('job_1'))
          .thenAnswer((_) async => sample.job());

      await env.runOk(['jobs', 'resume', 'job_1']);

      verify(() => env.client.resumeJob('job_1')).called(1);
    });

    test('resume can start at a step', () async {
      when(() => env.client.resumeJob('job_1', fromStep: 2))
          .thenAnswer((_) async => sample.job());

      await env.runOk(['jobs', 'resume', 'job_1', '--from-step', '2']);

      verify(() => env.client.resumeJob('job_1', fromStep: 2)).called(1);
    });

    test('resume refuses a step that is not a number', () async {
      expect(
        await env.run(['jobs', 'resume', 'job_1', '--from-step', 'x']),
        64,
      );
    });
  });

  group('logs', () {
    setUp(() {
      when(() => env.client.getJob('job_1'))
          .thenAnswer((_) async => sample.job());
    });

    LogLineFrame line(int seq) => LogLineFrame(
      seq: seq,
      step: 0,
      at: sample.at,
      stream: LogStream.stdout,
      text: 'line $seq',
    );

    Future<int> Function(List<String>) logs(Stream<LogFrame> frames) {
      when(() => env.client.followJobLogs('job_1', after: any(named: 'after')))
          .thenAnswer((_) => frames);
      return env.run;
    }

    test('prints the lines and how the job ended', () async {
      final run = logs(
        Stream.fromIterable([
          line(1),
          line(2),
          const LogEndFrame(state: JobState.succeeded),
        ]),
      );

      expect(await run(['logs', 'job_1']), 0);

      expect(env.logger.infos, ['line 1', 'line 2', '-- job succeeded']);
    });

    test('without -f stops when the engine is quiet', () async {
      final controller = StreamController<LogFrame>();
      addTearDown(controller.close);
      final run = logs(controller.stream);
      controller.add(line(1));

      expect(await run(['logs', 'job_1']), 0);

      expect(env.logger.infos, ['line 1']);
    });

    test('without -f reads the whole log of a job that ended', () async {
      when(() => env.client.getJob('job_1'))
          .thenAnswer((_) async => sample.job(state: JobState.succeeded));
      final controller = StreamController<LogFrame>();
      final run = logs(controller.stream);
      controller.add(line(1));
      // Slower than logIdle: a job that ended is read to its end.
      Timer(const Duration(milliseconds: 120), () {
        controller
          ..add(line(2))
          ..add(const LogEndFrame(state: JobState.succeeded));
        unawaited(controller.close());
      });

      expect(await run(['logs', 'job_1']), 0);

      expect(env.logger.infos, ['line 1', 'line 2', '-- job succeeded']);
    });

    test('with -f waits for the end and fails with a failed job', () async {
      final run = logs(
        Stream.fromIterable([
          line(1),
          const LogEndFrame(state: JobState.failed),
        ]),
      );

      expect(await run(['logs', 'job_1', '-f']), 1);

      expect(env.logger.infos.last, '-- job failed');
    });

    test('with -f a job that waits for approval is not a failure', () async {
      final run = logs(
        Stream.fromIterable([
          const LogEndFrame(state: JobState.waitingForApproval),
        ]),
      );

      expect(await run(['logs', 'job_1', '--follow']), 0);

      expect(env.logger.infos.last, '-- job waiting_for_approval');
    });

    test('without -f a failed job is still exit 0', () async {
      final run = logs(
        Stream.fromIterable([const LogEndFrame(state: JobState.failed)]),
      );

      expect(await run(['logs', 'job_1']), 0);
    });

    test('starts after a line', () async {
      logs(const Stream.empty());

      await env.run(['logs', 'job_1', '--after', '7']);

      verify(() => env.client.followJobLogs('job_1', after: 7)).called(1);
    });

    test('refuses a line that is not a number', () async {
      expect(await env.run(['logs', 'job_1', '--after', '-1']), 64);
      expect(await env.run(['logs', 'job_1', '--after', 'x']), 64);
    });

    test('with --json prints every frame as a line of JSON', () async {
      final run = logs(
        Stream.fromIterable([
          line(1),
          const LogGapFrame(fromSeq: 2, toSeq: 3, count: 2),
          const LogEndFrame(state: JobState.succeeded),
        ]),
      );

      await run(['--json', 'logs', 'job_1']);

      final frames = [
        for (final text in env.logger.infos)
          jsonDecode(text) as Map<String, dynamic>,
      ];
      expect(frames.map((frame) => frame['type']), ['line', 'gap', 'end']);
    });

    test('shows a gap as nothing in the text form', () async {
      final run = logs(
        Stream.fromIterable([
          const LogGapFrame(fromSeq: 2, toSeq: 3, count: 2),
        ]),
      );

      await run(['logs', 'job_1']);

      expect(env.logger.infos, isEmpty);
    });

    test('fails when the engine refuses', () async {
      when(() => env.client.followJobLogs('job_1', after: any(named: 'after')))
          .thenAnswer(
            (_) => Stream<LogFrame>.error(
              const ApiException(
                'No job.',
                statusCode: 404,
                code: ApiErrorCode.notFound,
              ),
            ),
          );

      expect(await env.run(['logs', 'job_1', '-f']), 66);
    });
  });
}
