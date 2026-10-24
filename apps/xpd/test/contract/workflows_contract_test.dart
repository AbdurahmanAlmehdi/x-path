@Tags(['contract'])
library;

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/test_engine.dart';
import '../helpers/workflow_helpers.dart';

/// Every response of the workflow and run endpoints is checked against
/// `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;
  late WorkflowClient client;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async {
    engine = await TestEngine.start();
    client = await WorkflowClient.add(engine);
  });
  tearDown(() => engine.close());

  void expectContract(
    RawResponse response, {
    required String path,
    required int status,
    String method = 'GET',
  }) {
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
  }

  test('request bodies match their schemas', () {
    for (final (schema, body) in <(String, Object)>[
      ('CreateWorkflowRequest', {'name': 'mine', 'yaml': 'schema: 1'}),
      ('WorkflowYamlRequest', {'yaml': 'schema: 1'}),
      ('DispatchRequest', <String, Object>{}),
      (
        'DispatchRequest',
        {
          'ref': 'release/1.2',
          'app': '.',
          'flavors': ['prod'],
          'platforms': ['android', 'ios'],
          'bump': 'minor',
          'version': '1.3.0',
          'releaseVersion': '1.2.0+45',
          'inputs': {
            'notes': 'x',
            'firebaseAppIds': {
              'dev': {'android': 'id'},
            },
          },
        },
      ),
    ]) {
      expect(contract.validateSchema(schema, body), isEmpty, reason: schema);
    }
    expect(
      contract.validateSchema('DispatchRequest', {'bump': 'huge'}),
      isNotEmpty,
    );
    expect(
      contract.validateSchema('DispatchRequest', {'releaseVersion': 'latest'}),
      isNotEmpty,
    );
  });

  group('workflows', () {
    test('GET schema 200 and 401', () async {
      final response = await client.send('GET', '/workflows/schema');
      final unauthorized = await engine.request('/workflows/schema', token: '');

      expectContract(response, path: '/workflows/schema', status: 200);
      expectContract(unauthorized, path: '/workflows/schema', status: 401);
    });

    test('GET list', () async {
      final response = await client.send('GET', client.base);

      expectContract(response, path: client.base, status: 200);
    });

    test('GET list 404 and 401', () async {
      final missing = await client.send('GET', '/projects/prj_nope/workflows');
      final unauthorized = await engine.request(client.base, token: '');

      expectContract(
        missing,
        path: '/projects/prj_nope/workflows',
        status: 404,
      );
      expectContract(unauthorized, path: client.base, status: 401);
    });

    test('POST create 201, 400, 409 and 422', () async {
      final created = await client.send('POST', client.base, {
        'name': 'mine',
        'yaml': echoWorkflow,
      });
      final badName = await client.send('POST', client.base, {
        'name': 'no spaces',
        'yaml': echoWorkflow,
      });
      final used = await client.send('POST', client.base, {
        'name': 'mine',
        'yaml': echoWorkflow,
      });
      final invalid = await client.send('POST', client.base, {
        'name': 'bad',
        'yaml': 'x: 1',
      });
      final malformed = await client.send('POST', client.base, {'name': 'x'});

      for (final (response, status) in [
        (created, 201),
        (badName, 400),
        (used, 409),
        (invalid, 422),
        (malformed, 400),
      ]) {
        expectContract(
          response,
          path: client.base,
          method: 'POST',
          status: status,
        );
      }
    });

    test('POST validate', () async {
      final path = '${client.base}/validate';

      expectContract(
        await client.send('POST', path, {'yaml': echoWorkflow}),
        path: path,
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', path, {'yaml': 'nope'}),
        path: path,
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', path, {}),
        path: path,
        method: 'POST',
        status: 400,
      );
    });

    test('GET templates 200 and 401', () async {
      final response = await client.send('GET', '/workflows/templates');
      final unauthorized = await engine.request(
        '/workflows/templates',
        token: '',
      );

      expectContract(response, path: '/workflows/templates', status: 200);
      expectContract(unauthorized, path: '/workflows/templates', status: 401);
    });

    test('POST validate without a project 200, 400 and 401', () async {
      const path = '/workflows/validate';

      for (final (response, status) in [
        (
          await client.send('POST', path, {'yaml': 'schema: 1\nstage: []'}),
          200,
        ),
        (await client.send('POST', path, {}), 400),
        (await engine.request(path, method: 'POST', token: ''), 401),
      ]) {
        expectContract(response, path: path, method: 'POST', status: status);
      }
    });

    test('GET one 200 and 404', () async {
      final id = await client.create('mine', echoWorkflow);
      final path = '${client.base}/$id';

      expectContract(await client.send('GET', path), path: path, status: 200);
      expectContract(
        await client.send('GET', '$path?version=1'),
        path: path,
        status: 200,
      );
      expectContract(
        await client.send('GET', '$path?version=3'),
        path: path,
        status: 404,
      );
      expectContract(
        await client.send('GET', '$path?version=x'),
        path: path,
        status: 400,
      );
    });

    test('GET one carries its typed inputs (UX-04)', () async {
      final id = await client.builtin('shorebird-patch');
      final path = '${client.base}/$id';

      final response = await client.send('GET', path);

      expectContract(response, path: path, status: 200);
      final inputs = response.json['inputs']! as List<Object?>;
      expect(inputs.first, {
        'name': 'releaseVersion',
        'type': 'release',
        'description':
            'The release the patch applies to, for example 5.4.1+3283. The '
            "dispatch's releaseVersion when it gives none.",
        'required': false,
      });
    });

    test('PUT 200, 404, 409 and 422', () async {
      final id = await client.create('mine', echoWorkflow);
      final builtin = await client.builtin('test');
      final path = '${client.base}/$id';

      expectContract(
        await client.send('PUT', path, {'yaml': echoWorkflow}),
        path: path,
        method: 'PUT',
        status: 200,
      );
      expectContract(
        await client.send('PUT', path, {'yaml': 'nope'}),
        path: path,
        method: 'PUT',
        status: 422,
      );
      expectContract(
        await client.send('PUT', '${client.base}/$builtin', {
          'yaml': echoWorkflow,
        }),
        path: '${client.base}/$builtin',
        method: 'PUT',
        status: 409,
      );
      expectContract(
        await client.send('PUT', '${client.base}/wf_nope', {
          'yaml': echoWorkflow,
        }),
        path: '${client.base}/wf_nope',
        method: 'PUT',
        status: 404,
      );
    });

    test('PATCH 200, 400, 404 and 409', () async {
      final id = await client.create('mine', echoWorkflow);
      final builtin = await client.builtin('test');

      for (final (path, body, status) in [
        ('${client.base}/$id', {'name': 'nightly', 'archived': true}, 200),
        ('${client.base}/$id', {'archived': 'yes'}, 400),
        ('${client.base}/wf_nope', {'archived': true}, 404),
        ('${client.base}/$builtin', {'archived': true}, 409),
      ]) {
        expectContract(
          await client.send('PATCH', path, body),
          path: path,
          method: 'PATCH',
          status: status,
        );
      }
    });

    test('DELETE 204, 404 and 409', () async {
      final id = await client.create('mine', echoWorkflow);
      final builtin = await client.builtin('test');

      expectContract(
        await client.send('DELETE', '${client.base}/$id'),
        path: '${client.base}/$id',
        method: 'DELETE',
        status: 204,
      );
      expectContract(
        await client.send('DELETE', '${client.base}/$id'),
        path: '${client.base}/$id',
        method: 'DELETE',
        status: 404,
      );
      expectContract(
        await client.send('DELETE', '${client.base}/$builtin'),
        path: '${client.base}/$builtin',
        method: 'DELETE',
        status: 409,
      );
    });
  });

  group('dispatch and runs', () {
    test('POST dispatch 202, 400, 404, 422, 502 and 503', () async {
      final id = await client.create('echo', echoWorkflow);
      final path = '${client.base}/$id/dispatch';

      final accepted = await client.dispatch(id);
      expectContract(accepted, path: path, method: 'POST', status: 202);
      expectContract(
        await client.dispatch(id, {'bump': 'huge'}),
        path: path,
        method: 'POST',
        status: 400,
      );
      expectContract(
        await client.dispatch(id, {
          'flavors': ['nope'],
        }),
        path: path,
        method: 'POST',
        status: 422,
      );
      expectContract(
        await client.dispatch('wf_nope'),
        path: '${client.base}/wf_nope/dispatch',
        method: 'POST',
        status: 404,
      );
      engine.git.fetchFailure = const GitException('down');
      expectContract(
        await client.dispatch(id),
        path: path,
        method: 'POST',
        status: 502,
      );
      engine.git.fetchFailure = const SecretsLockedException('locked');
      expectContract(
        await client.dispatch(id),
        path: path,
        method: 'POST',
        status: 503,
      );
    });

    test('POST dispatch?dryRun=true 200 and 400 (UX-01)', () async {
      final id = await client.builtin('dev-build');
      final path = '${client.base}/$id/dispatch';

      final planned = await client.send('POST', '$path?dryRun=true');

      expectContract(planned, path: path, method: 'POST', status: 200);
      final plan = DispatchPlan.fromJson(planned.json);
      expect(plan.build, 1);
      expect(
        plan.skipped.map((job) => job.reason),
        contains('no Firebase app id for default'),
      );
      expectContract(
        await client.send('POST', '$path?dryRun=maybe'),
        path: path,
        method: 'POST',
        status: 400,
      );
      final again = await client.send('POST', '$path?dryRun=true');
      expect(
        DispatchPlan.fromJson(again.json).build,
        1,
        reason: 'the dry run took no build number',
      );
    });

    test('GET runs 200, 400 and 404', () async {
      final id = await client.create('echo', echoWorkflow);
      final run = Run.fromJson((await client.dispatch(id)).json);
      await client.until(run.id, {RunState.succeeded});
      final project = '/projects/${client.projectId}/runs';

      for (final (path, status) in [
        ('/runs', 200),
        ('/runs?project=${client.projectId}&limit=1', 200),
        ('/runs?state=sleeping', 400),
        ('/runs?limit=0', 400),
        ('/runs?before=run_nope', 404),
        (project, 200),
        ('/projects/prj_nope/runs', 404),
      ]) {
        final response = await client.send('GET', path);
        expectContract(response, path: path.split('?').first, status: status);
      }
    });

    test('POST run-again 202 and 404, rerun-failed 200, 404 and 409', () async {
      var attempt = 0;
      engine.supervisor.handler = (process) => attempt++ == 0 ? 1 : 0;
      final id = await client.create('echo', echoWorkflow);
      final run = Run.fromJson((await client.dispatch(id)).json);
      await client.until(run.id, {RunState.failed});

      for (final (path, status) in [
        ('/runs/${run.id}/rerun-failed', 200),
        ('/runs/run_nope/rerun-failed', 404),
        ('/runs/run_nope/run-again', 404),
      ]) {
        expectContract(
          await client.send('POST', path),
          path: path,
          method: 'POST',
          status: status,
        );
      }
      await client.until(run.id, {RunState.succeeded});
      for (final (path, status) in [
        ('/runs/${run.id}/rerun-failed', 409),
        ('/runs/${run.id}/run-again', 202),
      ]) {
        expectContract(
          await client.send('POST', path),
          path: path,
          method: 'POST',
          status: status,
        );
      }
    });

    test('GET and cancel a run', () async {
      final id = await client.create('ship', gatedWorkflow);
      final run = Run.fromJson((await client.dispatch(id)).json);
      await client.until(run.id, {RunState.waitingForApproval});

      expectContract(
        await client.send('GET', '/runs/${run.id}'),
        path: '/runs/${run.id}',
        status: 200,
      );
      expectContract(
        await client.send('GET', '/runs/run_nope'),
        path: '/runs/run_nope',
        status: 404,
      );
      expectContract(
        await client.send('POST', '/runs/${run.id}/cancel'),
        path: '/runs/${run.id}/cancel',
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', '/runs/${run.id}/cancel'),
        path: '/runs/${run.id}/cancel',
        method: 'POST',
        status: 409,
      );
      expectContract(
        await client.send('POST', '/runs/run_nope/cancel'),
        path: '/runs/run_nope/cancel',
        method: 'POST',
        status: 404,
      );
    });

    test(
      'GET job of a dispatched run has its run, stage and capabilities',
      () async {
        final id = await client.create('echo', echoWorkflow);
        final run = Run.fromJson((await client.dispatch(id)).json);
        await client.until(run.id, {RunState.succeeded});

        final response = await client.send(
          'GET',
          '/jobs/${run.jobs.single.id}',
        );

        expectContract(
          response,
          path: '/jobs/${run.jobs.single.id}',
          status: 200,
        );
        expect(response.json['runId'], run.id);
        expect(response.json['stage'], 0);
      },
    );
  });
}
