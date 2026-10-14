import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

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
}
