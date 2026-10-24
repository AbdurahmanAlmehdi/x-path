import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

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

  var flows = 0;

  Future<Run> dispatch(String workflow) async {
    final id = await client.create('flow-${++flows}', workflow);
    return Run.fromJson((await client.dispatch(id)).json);
  }

  group('GET /runs', () {
    test('lists the runs newest first, wherever they came from', () async {
      final first = await dispatch(echoWorkflow);
      engine.clock.advance(const Duration(minutes: 1));
      final second = await dispatch(echoWorkflow);
      await client.until(first.id, {RunState.succeeded});
      await client.until(second.id, {RunState.succeeded});

      final all = RunsResponse.fromJson(
        (await client.send('GET', '/runs')).json,
      );
      expect(all.runs.map((r) => r.id), [second.id, first.id]);
      expect(all.runs.first.request, isNotNull);

      final page = RunsResponse.fromJson(
        (await client.send('GET', '/runs?limit=1&state=succeeded')).json,
      );
      expect(page.runs.single.id, second.id);
      expect(page.next, second.id);
      final rest = RunsResponse.fromJson(
        (await client.send('GET', '/runs?before=${page.next}')).json,
      );
      expect(rest.runs.single.id, first.id);

      final mine = RunsResponse.fromJson(
        (await client.send(
          'GET',
          '/projects/${client.projectId}/runs?workflow=${first.workflowId}',
        )).json,
      );
      expect(mine.runs.single.id, first.id);
    });

    test('answers 400 for a limit or a state it does not take', () async {
      for (final query in ['limit=0', 'limit=201', 'limit=x', 'state=x']) {
        final response = await client.send('GET', '/runs?$query');
        expect(response.statusCode, 400, reason: query);
      }
    });

    test('answers 404 for no project, and no run to page from', () async {
      expect(
        (await client.send('GET', '/projects/prj_nope/runs')).statusCode,
        404,
      );
      expect(
        (await client.send('GET', '/runs?before=run_nope')).statusCode,
        404,
      );
    });
  });

  group('GET /runs/{id}', () {
    test('shows a run with its jobs', () async {
      final run = await dispatch(echoWorkflow);

      final response = await client.send('GET', '/runs/${run.id}');

      expect(response.statusCode, 200);
      expect(Run.fromJson(response.json).id, run.id);
      await client.until(run.id, {RunState.succeeded});
    });

    test('answers 404 for an unknown run', () async {
      final response = await client.send('GET', '/runs/run_nope');

      expect(response.statusCode, 404);
      expect(
        (response.json['error']! as Map<String, dynamic>)['code'],
        'not_found',
      );
    });
  });

  group('POST /runs/{id}/run-again and rerun-failed', () {
    test('runs a run again as a new run of the same version', () async {
      final first = await dispatch(echoWorkflow);
      await client.until(first.id, {RunState.succeeded});

      final response = await client.send('POST', '/runs/${first.id}/run-again');

      expect(response.statusCode, 202);
      final again = Run.fromJson(response.json);
      expect(again.id, isNot(first.id));
      expect(again.workflowVersionId, first.workflowVersionId);
      expect(response.headers['location'], '/runs/${again.id}');
      expect(
        (await client.send('POST', '/runs/run_nope/run-again')).statusCode,
        404,
      );
    });

    test('runs the failed jobs of a run again', () async {
      var attempt = 0;
      engine.supervisor.handler = (process) => attempt++ == 0 ? 1 : 0;
      final run = await dispatch(echoWorkflow);
      await client.until(run.id, {RunState.failed});

      final response = await client.send(
        'POST',
        '/runs/${run.id}/rerun-failed',
      );

      expect(response.statusCode, 200);
      await client.until(run.id, {RunState.succeeded});
      final again = await client.send('POST', '/runs/${run.id}/rerun-failed');
      expect(again.statusCode, 409);
      expect(
        (await client.send('POST', '/runs/run_nope/rerun-failed')).statusCode,
        404,
      );
    });
  });

  group('POST /runs/{id}/cancel', () {
    test('cancels a run that waits for its turn', () async {
      final hold = Completer<void>();
      engine.supervisor.handler = (process) async {
        await hold.future;
        return 0;
      };
      final first = await dispatch(lockingWorkflow);
      await client.until(first.id, {RunState.running});
      final second = await dispatch(lockingWorkflow);

      final response = await client.send('POST', '/runs/${second.id}/cancel');

      expect(response.statusCode, 200);
      final run = Run.fromJson(response.json);
      expect(run.state, RunState.cancelled);
      expect(run.jobs.single.state, JobState.cancelled);
      hold.complete();
      await client.until(first.id, {RunState.succeeded});
    });

    test('cancels a run that is stopped at a gate', () async {
      final run = await dispatch(gatedWorkflow);
      await client.until(run.id, {RunState.waitingForApproval});

      final response = await client.send('POST', '/runs/${run.id}/cancel');

      expect(Run.fromJson(response.json).state, RunState.cancelled);
    });

    test('answers 409 for a run that ended', () async {
      final run = await dispatch(echoWorkflow);
      await client.until(run.id, {RunState.succeeded});

      final response = await client.send('POST', '/runs/${run.id}/cancel');

      expect(response.statusCode, 409);
      expect(
        (response.json['error']! as Map<String, dynamic>)['code'],
        'conflict',
      );
    });

    test('answers 404 for an unknown run', () async {
      final response = await client.send('POST', '/runs/run_nope/cancel');

      expect(response.statusCode, 404);
    });
  });

  test(
    'answers 409 when a job ended while the run was being cancelled',
    () async {
      final runs = InMemoryRunRepository();
      final jobs = InMemoryJobRepository();
      await runs.create(
        RunRecord(
          id: 'run_1',
          projectId: 'prj_1',
          workflowId: 'wf_1',
          workflowVersionId: 'wfv_1',
          sha: 'a' * 40,
          locksProject: false,
          createdAt: DateTime.utc(2026),
        ),
      );
      await jobs.create(
        JobRecord(
          id: 'job_1',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.queued,
          createdAt: DateTime.utc(2026),
          runId: 'run_1',
        ),
        const [],
      );
      final router = Router();
      RunsRoutes(RunService(runs: runs, jobs: jobs, control: _EndedJobs()))
          .addTo(router);

      final response = await router.call(
        Request('POST', Uri.parse('http://localhost/runs/run_1/cancel')),
      );

      expect(response.statusCode, 409);
    },
  );
}

/// A job control whose jobs have all ended by the time it is asked.
class _EndedJobs implements JobControl {
  @override
  Future<Job> cancel(String id) async =>
      throw const JobStateException('Job has ended.');

  @override
  Future<Job> get(String id) => throw UnimplementedError();

  @override
  Future<Job> resume(String id, {int? fromStep}) => throw UnimplementedError();
}
