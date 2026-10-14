import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

const _lease = Duration(seconds: 90);

void main() {
  late RunnerHarness h;

  setUp(() async => h = await RunnerHarness.create());
  tearDown(() => expect(h.errors, isEmpty));

  /// A runner that can sign, and a job that needs it.
  Future<(FakeRunner, String)> leased({List<StepPlan>? steps}) async {
    final runner = await h.online();
    final jobId = await h.job(needs: ['ios-sign'], steps: steps);
    await h.scheduler.pump();
    return (runner, jobId);
  }

  Future<List<JobState>> jobStates(String jobId) async => [
    for (final event in await h.eventsOf<JobStateChanged>())
      if (event.jobId == jobId) event.state,
  ];

  group('offer', () {
    test('leases a job the engine cannot do for 90 seconds', () async {
      final (runner, jobId) = await leased(
        steps: [h.script(), h.script(sideEffect: true)],
      );

      final job = await h.record(jobId);
      expect(job.state, JobState.running);
      expect(job.runnerId, runner.id);
      expect(job.leaseUntil, h.clock.now().add(_lease));
      expect(job.startedAt, h.clock.now());
      expect(h.hub.jobsOf(runner.id), [jobId]);
      final offer = runner.offer;
      expect(offer.jobId, jobId);
      expect(offer.leaseId, startsWith('lse_'));
      expect(offer.projectId, 'prj_1');
      expect(offer.sha, 'a' * 40);
      expect(offer.name, 'job 1');
      expect(offer.stage, 0);
      expect(offer.capabilities, ['ios-sign']);
      expect(offer.expiresAt, h.clock.now().add(_lease));
      expect(offer.secrets, isEmpty);
      expect(
        [
          for (final step in offer.steps)
            (
              step.ordinal,
              step.kind,
              step.sideEffect,
              step.state,
              step.attempts,
            ),
        ],
        [
          (0, 'scripted', false, StepState.pending, 0),
          (1, 'scripted', true, StepState.pending, 0),
        ],
      );
      expect(await jobStates(jobId), [JobState.queued, JobState.running]);
      expect(h.hub.holdsLease(runner.id, jobId, offer.leaseId), isTrue);
      expect(h.hub.holdsLease(runner.id, jobId, 'lse_other'), isFalse);
      expect(h.hub.holdsLease('rnr_other', jobId, offer.leaseId), isFalse);
    });

    test('never leases a job with a step only the engine runs', () async {
      final runner = await h.online();
      final jobId = await h.job(
        needs: ['ios-sign'],
        steps: [
          h.script(),
          const StepPlan(kind: 'upload.appStore', input: {}, sideEffect: true),
        ],
      );

      await h.scheduler.pump();

      expect(runner.offers, isEmpty);
      final job = await h.record(jobId);
      expect(job.state, JobState.queued);
      expect(
        job.message,
        'Only the engine runs upload.appStore, and the engine cannot do '
        'ios-sign.',
      );
      await expectLater(
        h.hub.offer(runner.id, jobId),
        throwsA(
          isA<JobStateException>().having(
            (e) => e.message,
            'message',
            contains('only the engine runs (upload.appStore)'),
          ),
        ),
      );
      expect(runner.offers, isEmpty);
    });

    test(
      'is refused for a runner that is not connected or a job not queued',
      () async {
        final runner = await h.online();
        final jobId = await h.job(needs: ['ios-sign']);

        await expectLater(
          h.hub.offer('rnr_nobody', jobId),
          throwsA(isA<JobStateException>()),
        );
        await expectLater(
          h.hub.offer(runner.id, 'job_nobody'),
          throwsA(isA<JobNotFoundException>()),
        );
        await h.hub.offer(runner.id, jobId);
        await expectLater(
          h.hub.offer(runner.id, jobId),
          throwsA(
            isA<JobStateException>().having(
              (e) => e.message,
              'message',
              contains('running, not queued'),
            ),
          ),
        );
      },
    );

    test(
      'puts a job back in the queue when the offer cannot be sent',
      () async {
        final runner = await h.online();
        runner.link.failToSend = true;
        final jobId = await h.job(needs: ['ios-sign']);

        await h.scheduler.pump();
        await h.settle();

        expect(runner.offers, isEmpty);
        expect((await h.record(jobId)).runnerId, isNull);
        expect(h.hub.jobsOf(runner.id), isEmpty);
        expect(await h.eventsOf<RunnerLeaseLost>(), [
          RunnerLeaseLost(
            runnerId: runner.id,
            jobId: jobId,
            projectId: 'prj_1',
            reason: 'offer_failed',
            state: JobState.queued,
          ),
        ]);
      },
    );

    test('the lease is accepted, once', () async {
      final (runner, jobId) = await leased();
      h.clock.advance(const Duration(seconds: 10));

      await runner.accept();
      await runner.accept();

      final job = await h.record(jobId);
      expect(job.state, JobState.running);
      expect(job.leaseUntil, h.clock.now().add(_lease));
    });

    test(
      'an accept for a lease the engine does not hold is cancelled',
      () async {
        final (runner, jobId) = await leased();

        await runner.send(LeaseAcceptFrame(jobId: jobId, leaseId: 'lse_wrong'));

        expect(runner.cancels.single.jobId, jobId);
        expect(runner.cancels.single.leaseId, 'lse_wrong');
        expect(runner.cancels.single.reason, contains('no such lease'));
        expect((await h.record(jobId)).state, JobState.running);
      },
    );
  });

  group('heartbeat', () {
    test('renews the lease and says until when', () async {
      final (runner, jobId) = await leased();
      await runner.accept();

      h.clock.advance(const Duration(seconds: 60));
      await runner.heartbeat();

      final until = h.clock.now().add(_lease);
      expect((await h.record(jobId)).leaseUntil, until);
      expect(runner.link.sentOf<HeartbeatAckFrame>().single.leases, [
        LeaseGrant(jobId: jobId, leaseId: runner.offer.leaseId, until: until),
      ]);
      // The first lease would have run out by now.
      h.clock.advance(const Duration(seconds: 40));
      await runner.heartbeat(const []);
      await h.hub.sweep();
      expect((await h.record(jobId)).state, JobState.running);
    });

    test('repeating it changes nothing but the time', () async {
      final (runner, jobId) = await leased();
      final before = (await h.eventsOf<JobStateChanged>()).length;

      await runner.heartbeat();
      await runner.heartbeat();

      final job = await h.record(jobId);
      expect(job.state, JobState.running);
      expect(job.leaseUntil, h.clock.now().add(_lease));
      expect(runner.link.sentOf<HeartbeatAckFrame>(), hasLength(2));
      expect(h.hub.jobsOf(runner.id), [jobId]);
      expect((await h.eventsOf<JobStateChanged>()).length, before);
    });

    test('cancels a lease the engine does not hold', () async {
      final (runner, jobId) = await leased();
      final other = await h.online(name: 'other');

      await runner.heartbeat([
        LeaseRef(jobId: jobId, leaseId: 'lse_wrong'),
        const LeaseRef(jobId: 'job_nobody', leaseId: 'lse_1'),
      ]);
      // The lease of one runner is not the lease of another.
      await other.heartbeat([runner.leaseOf()]);

      expect(runner.cancels.map((c) => c.jobId), [jobId, 'job_nobody']);
      expect(other.cancels.single.jobId, jobId);
      expect(runner.link.sentOf<HeartbeatAckFrame>().single.leases, isEmpty);
      expect((await h.record(jobId)).state, JobState.running);
      expect((await h.record(jobId)).runnerId, runner.id);
    });

    test('too late to renew: the lease is lost', () async {
      final (runner, jobId) = await leased();

      h.clock.advance(_lease);
      await runner.heartbeat();

      expect(runner.cancels.single.reason, 'The lease ran out.');
      expect(runner.link.sentOf<HeartbeatAckFrame>().single.leases, isEmpty);
      expect((await h.record(jobId)).runnerId, isNull);
      expect(h.hub.jobsOf(runner.id), isEmpty);
    });

    test('a job the engine ended is not renewed', () async {
      final (runner, jobId) = await leased();
      await h.jobs.runner.cancel(jobId);

      await runner.heartbeat();

      expect(runner.cancels.single.reason, 'The lease ran out.');
      expect((await h.record(jobId)).state, JobState.cancelled);
    });
  });

  group('lease lapse (D-08, 90 s)', () {
    test('a job without side effects is queued again', () async {
      final (runner, jobId) = await leased(steps: [h.script(), h.script()]);
      await runner.accept();
      await runner.step(0, StepState.succeeded);
      await runner.step(1, StepState.running);
      final lease = runner.leaseOf();

      h.clock.advance(const Duration(seconds: 89));
      await runner.heartbeat(const []);
      await h.hub.sweep();
      expect((await h.record(jobId)).state, JobState.running);

      h.clock.advance(const Duration(seconds: 1));
      await h.hub.sweep();
      await h.settle();

      // Lost, queued again, and offered again to the runner that is still
      // there, under a new lease.
      expect(await jobStates(jobId), [
        JobState.queued,
        JobState.running,
        JobState.interrupted,
        JobState.queued,
        JobState.running,
      ]);
      expect(runner.offers, hasLength(2));
      expect(runner.offer.leaseId, isNot(lease.leaseId));
      expect(
        [for (final step in runner.offer.steps) (step.state, step.attempts)],
        [(StepState.succeeded, 1), (StepState.interrupted, 1)],
      );
      expect(runner.cancels.single.leaseId, lease.leaseId);
      expect(runner.cancels.single.reason, contains('lapsed'));
      expect(await h.eventsOf<RunnerLeaseLost>(), [
        RunnerLeaseLost(
          runnerId: runner.id,
          jobId: jobId,
          projectId: 'prj_1',
          reason: 'lapsed',
          state: JobState.queued,
        ),
      ]);
    });

    test('a job that waits for no one is queued, with no owner', () async {
      final (runner, jobId) = await leased();
      await runner.accept();
      await runner.step(0, StepState.running);

      h.clock.advance(_lease);
      await h.hub.sweep();
      await h.settle();

      final job = await h.record(jobId);
      expect(job.state, JobState.queued);
      expect(job.runnerId, isNull);
      expect(job.leaseUntil, isNull);
      expect(job.finishedAt, isNull);
      expect((await h.steps(jobId)).single.state, StepState.interrupted);
      expect(
        job.message,
        'No runner can do ios-sign.',
        reason: 'the runner went quiet and was dropped',
      );
      expect(h.hub.isConnected(runner.id), isFalse);
    });

    test('a step with side effects is never queued again', () async {
      final (runner, jobId) = await leased(
        steps: [h.script(), h.script(sideEffect: true)],
      );
      await runner.accept();
      await runner.step(0, StepState.succeeded);
      await runner.step(1, StepState.running);

      h.clock.advance(_lease);
      await h.hub.sweep();
      await h.settle();

      final job = await h.record(jobId);
      expect(job.state, JobState.waitingForResume);
      expect(job.runnerId, isNull);
      expect(job.leaseUntil, isNull);
      expect(job.message, contains('side effects'));
      expect(job.message, contains('never repeated'));
      expect((await h.steps(jobId)).map((s) => s.state), [
        StepState.succeeded,
        StepState.interrupted,
      ]);
      expect(await h.eventsOf<RunnerLeaseLost>(), [
        RunnerLeaseLost(
          runnerId: runner.id,
          jobId: jobId,
          projectId: 'prj_1',
          reason: 'lapsed',
          state: JobState.waitingForResume,
        ),
      ]);
      // Nothing re-queues it, however long the scheduler looks.
      h.clock.advance(const Duration(hours: 1));
      await runner.heartbeat(const []);
      await h.hub.sweep();
      await h.scheduler.pump();
      expect((await h.record(jobId)).state, JobState.waitingForResume);
      expect(runner.offers, hasLength(1));
    });

    test('a side effect to come counts as well', () async {
      final (runner, jobId) = await leased(
        steps: [h.script(), h.script(sideEffect: true)],
      );
      await runner.accept();
      await runner.step(0, StepState.running);

      h.clock.advance(_lease);
      await h.hub.sweep();

      expect((await h.record(jobId)).state, JobState.waitingForResume);
      expect(runner.offers, hasLength(1));
    });

    test('a side effect that is done does not', () async {
      final (runner, jobId) = await leased(
        steps: [h.script(sideEffect: true), h.script()],
      );
      await runner.accept();
      await runner.step(0, StepState.succeeded);
      await runner.step(1, StepState.running);

      h.clock.advance(_lease);
      await runner.heartbeat(const []);
      await h.hub.sweep();
      await h.settle();

      expect(runner.offers, hasLength(2));
      expect((await h.record(jobId)).state, JobState.running);
    });

    test('waiting for a resume ends with an explicit resume', () async {
      final (runner, jobId) = await leased(steps: [h.script(sideEffect: true)]);
      await runner.accept();
      await runner.step(0, StepState.running);
      h.clock.advance(_lease);
      await runner.heartbeat(const []);
      await h.hub.sweep();
      expect((await h.record(jobId)).state, JobState.waitingForResume);

      await h.scheduler.resume(jobId);
      await h.settle();

      expect(runner.offers, hasLength(2));
      expect(runner.offer.steps.single.state, StepState.interrupted);
      expect((await h.record(jobId)).state, JobState.running);
    });

    test('the sweep is idempotent and leaves live leases alone', () async {
      final (runner, jobId) = await leased();
      await runner.accept();

      h.clock.advance(const Duration(seconds: 30));
      await h.hub.sweep();
      await h.hub.sweep();
      h.clock.advance(_lease);
      await runner.heartbeat(const []);
      await h.hub.sweep();
      await h.hub.sweep();
      await h.settle();

      expect(await h.eventsOf<RunnerLeaseLost>(), hasLength(1));
      expect(runner.offers, hasLength(2));
      expect((await h.record(jobId)).state, JobState.running);
    });

    test('a runner that comes back after the loss is told to stop', () async {
      final (runner, jobId) = await leased(steps: [h.script(sideEffect: true)]);
      await runner.accept();
      final old = runner.leaseOf();
      h.clock.advance(_lease);
      await h.hub.sweep();

      final back = await h.reconnect(runner);
      await back.hello(leases: [old]);
      await back.send(
        LogChunkFrame(
          jobId: jobId,
          leaseId: old.leaseId,
          seq: 1,
          lines: const [],
        ),
      );
      await back.done(JobState.succeeded, lease: old);

      expect(back.cancels, hasLength(3));
      expect(back.cancels.every((c) => c.leaseId == old.leaseId), isTrue);
      expect((await h.record(jobId)).state, JobState.waitingForResume);
    });

    test('a lease outlives the connection until it runs out', () async {
      final (runner, jobId) = await leased();
      await runner.accept();
      await runner.connection.closed();

      h.clock.advance(const Duration(seconds: 80));
      await h.hub.sweep();
      expect((await h.record(jobId)).state, JobState.running);

      // It comes back in time and shows the lease it still holds.
      final back = await h.reconnect(runner);
      await back.hello(leases: [runner.leaseOf()]);
      await back.answerProbe(macProbe());
      expect(back.link.sentOf<HeartbeatAckFrame>().single.leases, hasLength(1));
      h.clock.advance(const Duration(seconds: 80));
      await h.hub.sweep();
      expect((await h.record(jobId)).state, JobState.running);
      expect(back.cancels, isEmpty);
    });

    test('a lease with nobody left lapses all the same', () async {
      final (runner, jobId) = await leased();
      await runner.accept();
      await runner.connection.closed();

      h.clock.advance(_lease);
      await h.hub.sweep();
      await h.settle();

      expect((await h.record(jobId)).state, JobState.queued);
      expect(runner.cancels, isEmpty, reason: 'there is nobody to tell');
    });

    test('a job the engine lost track of is still put back', () async {
      final runner = await h.online();
      final jobId = await h.job(needs: ['ios-sign']);
      // A job that runs on a runner according to the database, with no lease
      // in memory: the engine restarted without recovering it.
      final record = await h.record(jobId);
      await h.jobs.jobs.updateJob(
        record.copyWith(
          state: JobState.running,
          runnerId: runner.id,
          leaseUntil: h.clock.now().add(_lease),
        ),
      );

      h.clock.advance(_lease);
      await h.hub.sweep();

      expect((await h.record(jobId)).state, JobState.queued);
    });
  });

  group('reject', () {
    test('gives the job back and cools the runner off', () async {
      final (runner, jobId) = await leased();

      await runner.send(
        LeaseRejectFrame(
          jobId: jobId,
          leaseId: runner.offer.leaseId,
          reason: 'busy',
        ),
      );
      await h.settle();

      final job = await h.record(jobId);
      expect(job.state, JobState.queued);
      expect(job.runnerId, isNull);
      expect(job.leaseUntil, isNull);
      expect(job.startedAt, isNull);
      expect(h.hub.jobsOf(runner.id), isEmpty);
      // No loop: the runner gets no job for a while, then it is asked again.
      expect(runner.offers, hasLength(1));
      expect(h.hub.slotsOf(runner.id), 0);
      h.clock.advance(const Duration(seconds: 14));
      await runner.heartbeat(const []);
      await h.hub.sweep();
      expect(h.hub.slotsOf(runner.id), 0);
      h.clock.advance(const Duration(seconds: 1));
      await runner.heartbeat(const []);
      await h.hub.sweep();
      await h.settle();
      expect(h.hub.slotsOf(runner.id), 2);
      expect(runner.offers, hasLength(2));
    });

    test('a runner that drains is not asked again', () async {
      final (runner, jobId) = await leased();

      await runner.send(
        LeaseRejectFrame(
          jobId: jobId,
          leaseId: runner.offer.leaseId,
          reason: 'draining',
        ),
      );
      await h.settle();

      expect(h.hub.statusOf(runner.id), RunnerStatus.draining);
      expect(h.hub.slotsOf(runner.id), 0);
      expect((await h.record(jobId)).state, JobState.queued);
    });

    test('a refusal of a job that is not leased is cancelled', () async {
      final (runner, jobId) = await leased();

      await runner.send(
        LeaseRejectFrame(jobId: jobId, leaseId: 'lse_wrong', reason: 'busy'),
      );

      expect(runner.cancels, hasLength(1));
      expect((await h.record(jobId)).state, JobState.running);
    });
  });

  group('cancel', () {
    test('ends the job at once and tells the runner', () async {
      final (runner, jobId) = await leased(steps: [h.script(), h.script()]);
      await runner.accept();
      await runner.step(0, StepState.running);

      final cancelled = await h.scheduler.cancel(jobId);

      expect(cancelled.state, JobState.cancelled);
      expect(cancelled.message, 'Cancelled.');
      final job = await h.record(jobId);
      expect(job.state, JobState.cancelled);
      expect(job.leaseUntil, isNull);
      expect(job.finishedAt, h.clock.now());
      expect((await h.steps(jobId)).map((s) => s.state), [
        StepState.cancelled,
        StepState.pending,
      ]);
      expect(runner.cancels.single.reason, 'Cancelled.');
      expect(h.hub.jobsOf(runner.id), isEmpty);
      // Whatever the runner still says about the lease is cancelled again.
      await runner.step(0, StepState.succeeded);
      expect(runner.cancels, hasLength(2));
      expect((await h.steps(jobId)).first.state, StepState.cancelled);
    });

    test("is the scheduler's for jobs that run on the engine", () async {
      await h.online();
      final jobId = await h.job(steps: [h.script(block: true)]);
      await h.scheduler.pump();

      final cancelling = h.scheduler.cancel(jobId);
      h.localGate.complete();
      final cancelled = await cancelling;

      // The engine's own cancel ran: the job is over.
      expect(cancelled.state.isFinished, isTrue);
      expect(await h.hub.cancel(jobId), isFalse);
      expect(await h.hub.cancel('job_nobody'), isFalse);
    });
  });

  group('revoke', () {
    test('ends the leases of the runner at once', () async {
      final (runner, jobId) = await leased(
        steps: [h.script(), h.script(sideEffect: true)],
      );
      final other = await h.online(name: 'other');
      final second = await h.job(needs: ['android']);
      await runner.accept();
      await runner.step(0, StepState.running);

      final revoked = await h.service.revoke(runner.id, by: h.owner);
      await h.settle();

      expect(revoked.status, RunnerStatus.revoked);
      expect(runner.link.closeCode, runnerRevokedCloseCode);
      expect(h.hub.isConnected(runner.id), isFalse);
      expect(h.scheduler.runners.map((r) => r.id), ['local', other.id]);
      final job = await h.record(jobId);
      expect(job.state, JobState.waitingForResume);
      expect(job.runnerId, isNull);
      expect(await h.eventsOf<RunnerLeaseLost>(), [
        RunnerLeaseLost(
          runnerId: runner.id,
          jobId: jobId,
          projectId: 'prj_1',
          reason: 'revoked',
          state: JobState.waitingForResume,
        ),
      ]);
      expect(await h.eventsOf<RunnerRevoked>(), [
        RunnerRevoked(runnerId: runner.id, name: runner.record.name),
      ]);
      expect(await h.state(second), JobState.queued);
    });

    test('puts a job without side effects back in the queue', () async {
      final (runner, jobId) = await leased();
      final other = await h.online(name: 'other');
      await runner.accept();

      await h.service.revoke(runner.id, by: h.owner);
      await h.settle();

      // It runs again, on the runner that is left.
      final job = await h.record(jobId);
      expect(job.state, JobState.running);
      expect(job.runnerId, other.id);
      expect(other.offers.single.jobId, jobId);
    });
  });
}
