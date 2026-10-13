import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;

  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  Future<RawResponse> send(
    String method,
    String path, {
    Object? json,
    String? body,
    String? token,
  }) => engine.request(
    path,
    method: method,
    token: token,
    body: body ?? (json == null ? null : jsonEncode(json)),
  );

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  /// A job that fails at its second step.
  Future<Job> failedJob() async {
    engine.supervisor.handler = (process) =>
        process.spec.executable == 'bad' ? 1 : 0;
    final job = await engine.startJob(['good', 'bad', 'after']);
    return await engine.jobs.whenFinished(job.id);
  }

  group('GET /jobs/{id}', () {
    test('returns the job with its steps', () async {
      final created = await engine.createJob(['a', 'b'], sideEffect: true);

      final response = await send('GET', '/jobs/${created.id}');

      expect(response.statusCode, 200);
      final job = Job.fromJson(response.json);
      expect(job, created);
      expect(job.state, JobState.queued);
      expect(job.steps.map((s) => (s.ordinal, s.sideEffect)), [
        (0, true),
        (1, true),
      ]);
    });

    test('shows how a finished job ended', () async {
      final failed = await failedJob();

      final job = Job.fromJson((await send('GET', '/jobs/${failed.id}')).json);

      expect(job.state, JobState.failed);
      expect(job.steps.map((s) => s.state), [
        StepState.succeeded,
        StepState.failed,
        StepState.pending,
      ]);
    });

    test('answers 404 for an unknown job', () async {
      final response = await send('GET', '/jobs/job_nope');

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });
  });

  group('POST /jobs/{id}/cancel', () {
    test('stops a running job and returns it cancelled', () async {
      final started = Completer<void>();
      engine.supervisor.handler = (process) async {
        started.complete();
        await Completer<void>().future;
        return 0;
      };
      final created = await engine.startJob(['long']);
      await started.future;

      final response = await send('POST', '/jobs/${created.id}/cancel');

      expect(response.statusCode, 200, reason: response.body);
      final job = Job.fromJson(response.json);
      expect(job.state, JobState.cancelled);
      expect(job.steps.single.state, StepState.cancelled);
      expect(engine.supervisor.processes.single.wasCancelled, isTrue);
    });

    test('cancels a queued job at once', () async {
      final created = await engine.createJob(['x']);

      final response = await send('POST', '/jobs/${created.id}/cancel');

      expect(Job.fromJson(response.json).state, JobState.cancelled);
    });

    test('answers 409 for a job that ended', () async {
      final failed = await failedJob();

      final response = await send('POST', '/jobs/${failed.id}/cancel');

      expect(response.statusCode, 409);
      expect(errorCode(response), 'conflict');
    });

    test('answers 404 for an unknown job', () async {
      expect((await send('POST', '/jobs/job_nope/cancel')).statusCode, 404);
    });
  });

  group('POST /jobs/{id}/resume', () {
    test('runs a failed job again from its first unfinished step', () async {
      final failed = await failedJob();
      engine.supervisor.handler = (process) => 0;

      final response = await send('POST', '/jobs/${failed.id}/resume');

      expect(response.statusCode, 202, reason: response.body);
      expect(Job.fromJson(response.json).state, JobState.running);
      final job = await engine.jobs.whenFinished(failed.id);
      expect(job.state, JobState.succeeded);
      expect(engine.supervisor.specs.map((s) => s.executable), [
        'good',
        'bad',
        'bad',
        'after',
      ]);
    });

    test('with fromStep runs again from that step', () async {
      final failed = await failedJob();
      engine.supervisor.handler = (process) => 0;

      final response = await send(
        'POST',
        '/jobs/${failed.id}/resume',
        json: {'fromStep': 0},
      );

      expect(response.statusCode, 202, reason: response.body);
      await engine.jobs.whenFinished(failed.id);
      expect(engine.supervisor.specs.map((s) => s.executable).skip(2), [
        'good',
        'bad',
        'after',
      ]);
    });

    test('answers 400 for a body that is not valid', () async {
      final failed = await failedJob();

      for (final body in ['{', '[1]', '{"fromStep": "one"}']) {
        final response = await send(
          'POST',
          '/jobs/${failed.id}/resume',
          body: body,
        );

        expect(response.statusCode, 400, reason: body);
        expect(errorCode(response), 'invalid_request');
      }
    });

    test('answers 400 for a step the job does not have', () async {
      final failed = await failedJob();

      final response = await send(
        'POST',
        '/jobs/${failed.id}/resume',
        json: {'fromStep': 9},
      );

      expect(response.statusCode, 400);
      expect(errorCode(response), 'invalid_request');
    });

    test('answers 409 for a job that cannot be resumed', () async {
      final queued = await engine.createJob(['x']);

      final response = await send('POST', '/jobs/${queued.id}/resume');

      expect(response.statusCode, 409);
      expect(errorCode(response), 'conflict');
    });

    test('answers 404 for an unknown job', () async {
      expect((await send('POST', '/jobs/job_nope/resume')).statusCode, 404);
    });

    test('waits for an explicit resume after an interruption', () async {
      final started = Completer<void>();
      engine.supervisor.handler = (process) async {
        started.complete();
        await Completer<void>().future;
        return 0;
      };
      final created = await engine.createJob(['upload'], sideEffect: true);
      await engine.jobs.start(created.id);
      await started.future;
      await engine.jobs.interruptAll();

      final waiting = Job.fromJson(
        (await send('GET', '/jobs/${created.id}')).json,
      );
      engine.supervisor.handler = (process) => 0;
      final resumed = await send('POST', '/jobs/${created.id}/resume');

      expect(waiting.state, JobState.waitingForResume);
      expect(resumed.statusCode, 202);
      expect(
        (await engine.jobs.whenFinished(created.id)).state,
        JobState.succeeded,
      );
    });
  });

  test('every /jobs route needs a device token', () async {
    for (final (method, path) in [
      ('GET', '/jobs/job_1'),
      ('POST', '/jobs/job_1/cancel'),
      ('POST', '/jobs/job_1/resume'),
    ]) {
      final response = await send(method, path, token: '');

      expect(response.statusCode, 401, reason: '$method $path');
    }
  });

  test('job and step changes are announced on the event log', () async {
    final job = await engine.startJob(['x']);
    await engine.jobs.whenFinished(job.id);

    final stream = await engine.connect(after: 0);
    addTearDown(stream.close);
    final seen = <EngineEvent>[];
    while (seen.whereType<JobStateChanged>().length < 3) {
      seen.add((await stream.next()).event);
    }

    expect(seen.whereType<JobStateChanged>().map((e) => e.state), [
      JobState.queued,
      JobState.running,
      JobState.succeeded,
    ]);
    expect(seen.whereType<JobStepChanged>().map((e) => (e.ordinal, e.state)), [
      (0, StepState.running),
      (0, StepState.succeeded),
    ]);
  });
}
