import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';
import '../../../helpers/workflow_helpers.dart';

void main() {
  late TestEngine engine;
  late WorkflowClient client;

  setUp(() async {
    engine = await TestEngine.start();
    client = await WorkflowClient.add(engine);
  });
  tearDown(() => engine.close());

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  String errorMessage(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['message']! as String;

  group('GET /workflows/schema', () {
    test('names what a workflow document may use', () async {
      final response = await client.send('GET', '/workflows/schema');

      expect(response.statusCode, 200);
      final schema = WorkflowSchema.fromJson(response.json);
      expect(schema.schema, 1);
      expect(schema.steps.map((step) => step.kind), contains('build.ios'));
      expect(schema.gates, contains('push'));
      final ios = schema.steps.firstWhere((step) => step.kind == 'build.ios');
      expect(ios.title, 'Build iOS');
      expect(
        ios.keys.firstWhere((key) => key.name == 'exportOptionsPlist').required,
        isTrue,
      );
      expect(schema.gateLabels['push'], 'Push');
      expect(schema.variables, contains('flavor.prod'));
    });

    test('needs a token', () async {
      final response = await engine.request('/workflows/schema', token: '');

      expect(response.statusCode, 401);
    });
  });

  group('GET /projects/{id}/workflows', () {
    test('lists the built-in workflows of the project', () async {
      final response = await client.send('GET', client.base);

      expect(response.statusCode, 200);
      final workflows = WorkflowsResponse.fromJson(response.json).workflows;
      expect(workflows.map((w) => w.name), [
        'dev-build',
        'prod-release',
        'release-merge',
        'shorebird-patch',
        'test',
      ]);
      expect(
        workflows.every((w) => w.builtin && w.version.version == 1),
        isTrue,
      );
    });

    test('answers 404 for an unknown project', () async {
      final response = await client.send('GET', '/projects/prj_nope/workflows');

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });

    test('needs a token', () async {
      final response = await engine.request(client.base, token: '');

      expect(response.statusCode, 401);
    });
  });

  group('POST /projects/{id}/workflows', () {
    test('creates a workflow at version 1', () async {
      final response = await client.send('POST', client.base, {
        'name': 'mine',
        'yaml': echoWorkflow,
      });

      expect(response.statusCode, 201);
      final workflow = Workflow.fromJson(response.json);
      expect(workflow.name, 'mine');
      expect(workflow.builtin, isFalse);
      expect(workflow.version.version, 1);
      expect(workflow.yaml, echoWorkflow);
      expect(response.headers['location'], '${client.base}/${workflow.id}');
    });

    test('answers 409 for a name that is used', () async {
      await client.create('mine', echoWorkflow);

      for (final name in ['mine', 'dev-build']) {
        final response = await client.send('POST', client.base, {
          'name': name,
          'yaml': echoWorkflow,
        });

        expect(response.statusCode, 409, reason: name);
        expect(errorCode(response), 'conflict');
      }
    });

    test('answers 400 for a name that is not allowed', () async {
      final response = await client.send('POST', client.base, {
        'name': 'no spaces',
        'yaml': echoWorkflow,
      });

      expect(response.statusCode, 400);
      expect(errorMessage(response), contains('is not a workflow name'));
    });

    test(
      'answers 422 with the issues of a document that is not valid',
      () async {
        final response = await client.send('POST', client.base, {
          'name': 'bad',
          'yaml': 'schema: 1\nstages: []',
        });

        expect(response.statusCode, 422);
        expect(errorCode(response), 'workflow_invalid');
        expect(
          errorMessage(response),
          'The workflow has 1 issue: line 2, column 9: "stages" is a list with '
          'at least one stage.',
        );
        expect(ErrorResponse.fromJson(response.json).error.issues, const [
          WorkflowIssue(
            line: 2,
            column: 9,
            message: '"stages" is a list with at least one stage.',
          ),
        ]);
      },
    );

    test('answers 400 for a body that is not a request', () async {
      final response = await client.send('POST', client.base, {'name': 'x'});

      expect(response.statusCode, 400);
      expect(errorCode(response), 'invalid_request');
    });

    test('announces the new workflow', () async {
      final id = await client.create('mine', echoWorkflow);

      final seen = <EngineEvent>[];
      final subscription = engine.events
          .subscribe(after: 0)
          .listen((e) => seen.add(e.event));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(
        seen.whereType<WorkflowSaved>().single,
        WorkflowSaved(
          workflowId: id,
          projectId: client.projectId,
          name: 'mine',
          version: 1,
        ),
      );
    });
  });

  group('POST /projects/{id}/workflows/validate', () {
    test('says valid for a good document, without saving it', () async {
      final response = await client.send('POST', '${client.base}/validate', {
        'yaml': echoWorkflow,
      });

      expect(response.statusCode, 200);
      expect(response.json, {'valid': true, 'issues': <Object?>[]});
    });

    test('lists the issues with line and column', () async {
      final response = await client.send('POST', '${client.base}/validate', {
        'yaml': 'schema: 1\nname: 3\nstages: []',
      });

      expect(response.statusCode, 200);
      final result = ValidateWorkflowResponse.fromJson(response.json);
      expect(result.valid, isFalse);
      expect(result.issues.map((i) => (i.line, i.column)), [(2, 7), (3, 9)]);
    });

    test('answers 400 for a body without yaml', () async {
      final response = await client.send('POST', '${client.base}/validate', {});

      expect(response.statusCode, 400);
    });
  });

  group('POST /workflows/validate', () {
    test('checks a document without a project, with hints', () async {
      final response = await client.send('POST', '/workflows/validate', {
        'yaml': 'schema: 1\nstage: []\n',
      });

      expect(response.statusCode, 200);
      final result = ValidateWorkflowResponse.fromJson(response.json);
      expect(result.valid, isFalse);
      expect(result.issues.first.hint, 'Did you mean "stages"?');
    });

    test('answers 401 without a token', () async {
      final response = await engine.request(
        '/workflows/validate',
        method: 'POST',
        token: '',
      );

      expect(response.statusCode, 401);
    });
  });

  group('GET /projects/{id}/workflows/{workflowId}', () {
    test('shows the newest version, or the one asked for', () async {
      final id = await client.create('mine', echoWorkflow);
      await client.send('PUT', '${client.base}/$id', {
        'yaml': '$echoWorkflow# two\n',
      });

      final newest = Workflow.fromJson(
        (await client.send('GET', '${client.base}/$id')).json,
      );
      final first = Workflow.fromJson(
        (await client.send('GET', '${client.base}/$id?version=1')).json,
      );

      expect(newest.version.version, 2);
      expect(newest.yaml, '$echoWorkflow# two\n');
      expect(newest.versions.map((v) => v.version), [1, 2]);
      expect(first.version.version, 1);
      expect(first.yaml, echoWorkflow);
    });

    test('answers 404 for an unknown workflow or version', () async {
      final id = await client.create('mine', echoWorkflow);

      expect(
        (await client.send('GET', '${client.base}/wf_nope')).statusCode,
        404,
      );
      final missing = await client.send('GET', '${client.base}/$id?version=7');
      expect(missing.statusCode, 404);
      expect(errorMessage(missing), contains('no version 7'));
    });

    test('answers 400 for a version that is not a positive number', () async {
      final id = await client.create('mine', echoWorkflow);

      for (final version in ['x', '0', '-2']) {
        final response = await client.send(
          'GET',
          '${client.base}/$id?version=$version',
        );

        expect(response.statusCode, 400, reason: version);
      }
    });
  });

  group('PUT /projects/{id}/workflows/{workflowId}', () {
    test('saves a new version', () async {
      final id = await client.create('mine', echoWorkflow);

      final response = await client.send('PUT', '${client.base}/$id', {
        'yaml': '$echoWorkflow# two\n',
      });

      expect(response.statusCode, 200);
      expect(Workflow.fromJson(response.json).version.version, 2);
    });

    test('answers 409 for a built-in workflow', () async {
      final id = await client.builtin('test');

      final response = await client.send('PUT', '${client.base}/$id', {
        'yaml': echoWorkflow,
      });

      expect(response.statusCode, 409);
      expect(errorMessage(response), contains('built-in'));
    });

    test(
      'answers 422 for a document with issues, 404 for no workflow',
      () async {
        final id = await client.create('mine', echoWorkflow);

        final invalid = await client.send('PUT', '${client.base}/$id', {
          'yaml': 'x: 1',
        });
        final missing = await client.send('PUT', '${client.base}/wf_nope', {
          'yaml': echoWorkflow,
        });

        expect(invalid.statusCode, 422);
        expect(missing.statusCode, 404);
      },
    );
  });

  group('DELETE /projects/{id}/workflows/{workflowId}', () {
    test('deletes a workflow of the owner', () async {
      final id = await client.create('mine', echoWorkflow);

      final response = await client.send('DELETE', '${client.base}/$id');

      expect(response.statusCode, 204);
      expect((await client.send('GET', '${client.base}/$id')).statusCode, 404);
    });

    test('answers 409 for a built-in workflow and for one jobs ran', () async {
      final builtin = await client.builtin('test');
      final id = await client.create('mine', echoWorkflow);
      final version = Workflow.fromJson(
        (await client.send('GET', '${client.base}/$id')).json,
      ).version.id;
      engine.workflowRepository.usedVersions.add(version);

      expect(
        (await client.send('DELETE', '${client.base}/$builtin')).statusCode,
        409,
      );
      final inUse = await client.send('DELETE', '${client.base}/$id');
      expect(inUse.statusCode, 409);
      expect(errorMessage(inUse), contains('has been run'));
    });

    test('answers 404 for an unknown workflow', () async {
      expect(
        (await client.send('DELETE', '${client.base}/wf_nope')).statusCode,
        404,
      );
    });
  });

  group('POST /projects/{id}/workflows/{workflowId}/dispatch', () {
    test('runs the workflow through the scheduler', () async {
      final id = await client.create('echo', echoWorkflow);

      final response = await client.dispatch(id);

      expect(response.statusCode, 202);
      final run = Run.fromJson(response.json);
      expect(response.headers['location'], '/runs/${run.id}');
      expect(run.workflowId, id);
      expect(run.sha, 'a' * 40);
      expect(run.ref, 'main');
      expect(run.locksProject, isFalse);
      expect(run.jobs.single.name, 'Echo');
      final done = await client.until(run.id, {RunState.succeeded});
      expect(done.jobs.single.state, JobState.succeeded);
      final job = Job.fromJson(
        (await client.send('GET', '/jobs/${done.jobs.single.id}')).json,
      );
      expect(job.runId, run.id);
      expect(job.steps.map((s) => s.kind), ['git.checkout', 'command']);
      expect(job.steps.every((s) => s.state == StepState.succeeded), isTrue);
    });

    test('takes the request from the body', () async {
      final id = await client.create('echo', echoWorkflow);

      final run = Run.fromJson(
        (await client.dispatch(id, {
          'ref': 'main',
          'inputs': <String, dynamic>{},
        })).json,
      );

      expect(run.ref, 'main');
    });

    test('announces the run', () async {
      final id = await client.create('echo', echoWorkflow);
      final run = Run.fromJson((await client.dispatch(id)).json);

      final seen = <EngineEvent>[];
      final subscription = engine.events
          .subscribe(after: 0)
          .listen((e) => seen.add(e.event));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(
        seen.whereType<RunDispatched>().single.jobIds,
        run.jobs.map((j) => j.id).toList(),
      );
    });

    test('answers 422 when the request cannot be done', () async {
      final id = await client.create('echo', echoWorkflow);

      final response = await client.dispatch(id, {
        'platforms': ['windows'],
      });

      expect(response.statusCode, 422);
      expect(errorCode(response), 'workflow_invalid');
      expect(errorMessage(response), contains('Unknown platform "windows"'));
    });

    test('answers 400 for a body that is not a request', () async {
      final id = await client.create('echo', echoWorkflow);

      final response = await client.dispatch(id, {'platforms': 3});

      expect(response.statusCode, 400);
    });

    test('answers 404 for an unknown workflow', () async {
      final response = await client.dispatch('wf_nope');

      expect(response.statusCode, 404);
    });

    test('answers 502 when the mirror cannot be fetched', () async {
      final id = await client.create('echo', echoWorkflow);
      engine.git.fetchFailure = const GitException('network down');

      final response = await client.dispatch(id);

      expect(response.statusCode, 502);
      expect(errorCode(response), 'upstream_error');
      expect(errorMessage(response), 'network down');
    });

    test('answers 503 while the secrets are locked', () async {
      final id = await client.create('echo', echoWorkflow);
      engine.git.fetchFailure = const SecretsLockedException('locked');

      final response = await client.dispatch(id);

      expect(response.statusCode, 503);
      expect(errorCode(response), 'secrets_locked');
    });

    test('queues a second production release behind the first', () async {
      final id = await client.create('release', lockingWorkflow);
      final release = Completer<void>();
      engine.supervisor.handler = (process) async {
        await release.future;
        return 0;
      };

      final first = Run.fromJson((await client.dispatch(id)).json);
      final second = Run.fromJson((await client.dispatch(id)).json);

      await client.until(first.id, {RunState.running});
      final waiting = Job.fromJson(
        (await client.send('GET', '/jobs/${second.jobs.single.id}')).json,
      );
      expect(waiting.state, JobState.queued);
      expect(
        waiting.message,
        'Waiting for run ${first.id} to finish: only one production release '
        'or patch of a project runs at a time.',
      );
      expect(
        (await client.send('GET', '/runs/${second.id}')).json['state'],
        'queued',
      );

      release.complete();
      await client.until(first.id, {RunState.succeeded});
      await client.until(second.id, {RunState.succeeded});
    });

    test('stops at a gate until the owner approves, then goes on', () async {
      final id = await client.create('ship', gatedWorkflow);

      final run = Run.fromJson((await client.dispatch(id)).json);
      final waiting = await client.until(run.id, {RunState.waitingForApproval});

      expect(waiting.jobs.single.state, JobState.waitingForApproval);
      expect(waiting.jobs.single.message, contains('prod_release'));
      final request = engine.gate.requests.single;
      expect(request.action, GateAction.prodRelease);
      expect(request.projectId, client.projectId);
      expect(request.sha, 'a' * 40);

      engine.gate.decision = const GateApproved();
      await engine.scheduler.resumeWaiting(projectId: client.projectId);

      await client.until(run.id, {RunState.succeeded});
    });

    test('fails the job when the owner denies the gate', () async {
      final id = await client.create('ship', gatedWorkflow);
      engine.gate.decision = const GateDenied('Not today.');

      final run = Run.fromJson((await client.dispatch(id)).json);

      final failed = await client.until(run.id, {RunState.failed});
      expect(failed.jobs.single.message, contains('Not today.'));
    });
  });
}
