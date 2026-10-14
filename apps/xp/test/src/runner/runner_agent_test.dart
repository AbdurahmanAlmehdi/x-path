import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xp/src/runner/backoff.dart';
import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp/src/runner/probe_executor.dart';
import 'package:xp/src/runner/runner_agent.dart';
import 'package:xp/src/runner/runner_socket.dart';
import 'package:xp/src/runner/secrets/lease_secret_store.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_fakes.dart';

class _Started {
  const new(this.work, this.requestSecret);

  final FakeLeaseWork work;
  final SecretRequester requestSecret;

  LeaseOutbox get outbox => work.outbox;
}

void main() {
  late List<Object> connections;
  late List<String> log;
  late List<Duration> waited;
  late List<_Started> started;
  late FakeProcessRunner processes;

  FakeRunnerSocket socket() {
    final fake = FakeRunnerSocket();
    connections.add(fake);
    return fake;
  }

  RunnerAgent agent({
    int slots = 2,
    int? requestedSlots,
    bool oneShot = false,
    Set<String> kinds = const {'command', 'build.android'},
    Duration secretTimeout = const Duration(seconds: 5),
    Future<void> Function(Duration)? delay,
    Duration Function(int)? heartbeatUnit,
  }) => RunnerAgent(
    connect: () async {
      final next = connections.removeAt(0);
      if (next is RunnerSocket) return next;
      throw next as Exception;
    },
    start: (offer, outbox, requestSecret) {
      final work = FakeLeaseWork(offer, outbox);
      started.add(_Started(work, requestSecret));
      return work;
    },
    probe: ProbeExecutor(runner: processes, operatingSystem: 'macos'),
    stepKinds: kinds,
    log: log.add,
    version: '1.2.3',
    os: 'macos',
    arch: 'arm64',
    cores: 8,
    slots: slots,
    requestedSlots: requestedSlots,
    oneShot: oneShot,
    secretTimeout: secretTimeout,
    backoff: Backoff(random: _FixedRandom()),
    delay:
        delay ??
        (duration) async {
          waited.add(duration);
        },
    heartbeatUnit: heartbeatUnit ?? ((seconds) => Duration(seconds: seconds)),
  );

  setUp(() {
    connections = [];
    log = [];
    waited = [];
    started = [];
    processes = FakeProcessRunner(
      (call) => ProcessOutput(exitCode: 0, stdout: '${call.executable}\n'),
    );
  });

  /// Welcomes the runner on [fake] and waits until it said hello.
  Future<void> welcome(
    FakeRunnerSocket fake, {
    int heartbeatSeconds = 30,
  }) async {
    fake.engine(
      WelcomeFrame(
        runnerId: 'rnr_1',
        engineVersion: '9.9.9',
        apiVersion: apiVersion,
        heartbeatSeconds: heartbeatSeconds,
      ),
    );
    await pumpEventQueue();
  }

  Future<void> offer(
    FakeRunnerSocket fake,
    String jobId, {
    String leaseId = 'lse_1',
    List<String> kinds = const ['command'],
    List<String> capabilities = const [],
    List<String> secrets = const [],
  }) async {
    fake.engine(
      offerOf(
        jobId,
        leaseId: leaseId,
        kinds: kinds,
        capabilities: capabilities,
        secrets: secrets,
      ),
    );
    await pumpEventQueue();
  }

  group('the hello', () {
    test('says who the runner is once the engine welcomed it', () async {
      final fake = socket();
      final running = agent(requestedSlots: 3).run();
      await pumpEventQueue();
      expect(fake.sent, isEmpty, reason: 'the engine speaks first');

      await welcome(fake);

      final hello = fake.sentOf<HelloFrame>().single;
      expect(hello.version, '1.2.3');
      expect(hello.os, 'macos');
      expect(hello.arch, 'arm64');
      expect(hello.cores, 8);
      expect(hello.maxJobs, 3);
      expect(hello.draining, isFalse);
      expect(hello.leases, isEmpty);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test(
      'leaves the number of slots to the engine unless it is told',
      () async {
        final fake = socket();
        final running = agent().run();
        await pumpEventQueue();
        await welcome(fake);

        expect(fake.sentOf<HelloFrame>().single.maxJobs, isNull);
        await fake.engineCloses(runnerRevokedCloseCode);
        await running;
      },
    );
  });

  group('the probe', () {
    test(
      'runs the commands of the engine and answers with the results',
      () async {
        final fake = socket();
        final running = agent().run();
        await pumpEventQueue();
        await welcome(fake);

        fake.engine(
          const ProbeFrame(
            probeId: 'prb_1',
            commands: [
              ProbeCommand(
                id: 'git',
                executable: 'git',
                arguments: ['--version'],
              ),
              ProbeCommand(id: 'swift', executable: 'swift', onlyOn: 'linux'),
            ],
          ),
        );
        await pumpEventQueue();

        final result = fake.sentOf<ProbeResultFrame>().single;
        expect(result.probeId, 'prb_1');
        expect(
          [for (final r in result.results) (r.id, r.status)],
          [('git', ProbeStatus.exited), ('swift', ProbeStatus.skipped)],
        );
        await fake.engineCloses(runnerRevokedCloseCode);
        await running;
      },
    );
  });

  group('the heartbeat', () {
    test(
      'is sent every heartbeatSeconds of the welcome, with the leases',
      () async {
        final fake = socket();
        final running = agent(
          heartbeatUnit: (seconds) => Duration(milliseconds: 20 * seconds),
        ).run();
        await pumpEventQueue();
        await welcome(fake, heartbeatSeconds: 1);
        await offer(fake, 'job_1');

        await Future<void>.delayed(const Duration(milliseconds: 70));

        final beats = fake.sentOf<HeartbeatFrame>();
        expect(beats.length, greaterThanOrEqualTo(2));
        expect(beats.last.leases, [
          const LeaseRef(jobId: 'job_1', leaseId: 'lse_1'),
        ]);
        await fake.engineCloses(runnerRevokedCloseCode);
        await running;
      },
    );

    test('stops with the connection', () async {
      final fake = socket();
      final running = agent(
        heartbeatUnit: (seconds) => Duration(milliseconds: 10 * seconds),
      ).run();
      await pumpEventQueue();
      await welcome(fake, heartbeatSeconds: 1);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
      final before = fake.sentOf<HeartbeatFrame>().length;

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fake.sentOf<HeartbeatFrame>(), hasLength(before));
    });
  });

  group('an offer', () {
    test('is accepted within the slots, and the job starts', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);

      await offer(fake, 'job_1');

      expect(fake.sentOf<LeaseAcceptFrame>().single.jobId, 'job_1');
      expect(started, hasLength(1));
      expect(started.single.work.offer.leaseId, 'lse_1');
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('is refused when the slots are taken', () async {
      final fake = socket();
      final running = agent(slots: 1).run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      await offer(fake, 'job_2', leaseId: 'lse_2');

      expect(fake.sentOf<LeaseRejectFrame>().single.reason, 'busy');
      expect(started, hasLength(1));
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('is refused when an ios-sign job runs already', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1', capabilities: ['ios-sign']);

      await offer(fake, 'job_2', leaseId: 'lse_2', capabilities: ['ios-sign']);
      await offer(fake, 'job_3', leaseId: 'lse_3', capabilities: ['android']);

      expect(fake.sentOf<LeaseRejectFrame>().map((r) => (r.jobId, r.reason)), [
        ('job_2', 'busy'),
      ]);
      expect(started.map((s) => s.work.offer.jobId), ['job_1', 'job_3']);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('is refused when it has a step this runner cannot run', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);

      await offer(fake, 'job_1', kinds: ['command', 'upload.play']);

      final reject = fake.sentOf<LeaseRejectFrame>().single;
      expect(reject.reason, startsWith('unsupported'));
      expect(reject.reason, contains('upload.play'));
      expect(started, isEmpty);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('is refused when the job runs here already', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      await offer(fake, 'job_1', leaseId: 'lse_2');

      expect(fake.sentOf<LeaseRejectFrame>().single.reason, 'busy');
      expect(started, hasLength(1));
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('is refused while draining, and the drain is announced', () async {
      final fake = socket();
      final agent0 = agent();
      final running = agent0.run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      agent0.drain();
      await offer(fake, 'job_2', leaseId: 'lse_2');

      expect(agent0.isDraining, isTrue);
      expect(fake.sentOf<DrainFrame>().single.draining, isTrue);
      expect(fake.sentOf<LeaseRejectFrame>().single.reason, 'draining');
      started.single.work.finish();
      started.single.outbox.finish(state: JobState.succeeded);
      fake.engine(
        const DoneAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          state: JobState.succeeded,
        ),
      );
      expect(await running, AgentExit.drained);
    });
  });

  group('the report of a job', () {
    test(
      'is kept until acknowledged and sent again after a reconnect',
      () async {
        final first = socket();
        final second = socket();
        final running = agent().run();
        await pumpEventQueue();
        await welcome(first);
        await offer(first, 'job_1');
        final outbox = started.single.outbox
          ..line(
            ChunkLine(
              step: 0,
              at: DateTime.utc(2026),
              stream: LogStream.stdout,
              text: 'hello',
            ),
          )
          ..flush()
          ..step(
            const StepStateFrame(
              jobId: 'job_1',
              leaseId: 'lse_1',
              ordinal: 0,
              state: StepState.running,
              attempts: 1,
            ),
          );
        started.single.work.finish();
        outbox.finish(state: JobState.succeeded);
        await pumpEventQueue();
        expect(first.sentOf<LogChunkFrame>(), hasLength(1));
        expect(first.sentOf<JobDoneFrame>(), hasLength(1));

        // The connection drops before the engine acknowledged anything.
        await first.engineCloses();
        await pumpEventQueue();
        await welcome(second);

        final hello = second.sentOf<HelloFrame>().single;
        expect(hello.leases, [
          const LeaseRef(jobId: 'job_1', leaseId: 'lse_1'),
        ]);
        expect(second.sentOf<LogChunkFrame>().single.seq, 1);
        expect(second.sentOf<StepStateFrame>(), hasLength(1));
        expect(second.sentOf<JobDoneFrame>().single.lastChunk, 1);
        second.engine(
          const DoneAckFrame(
            jobId: 'job_1',
            leaseId: 'lse_1',
            state: JobState.succeeded,
          ),
        );
        await pumpEventQueue();
        expect(log.last, contains('job_1 ended'));
        await second.engineCloses(runnerRevokedCloseCode);
        await running;
      },
    );

    test('goes on where the engine says after a gap', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');
      final outbox = started.single.outbox;
      for (final text in ['a', 'b']) {
        outbox
          ..line(
            ChunkLine(
              step: 0,
              at: DateTime.utc(2026),
              stream: LogStream.stdout,
              text: text,
            ),
          )
          ..flush();
      }
      fake.sent.clear();

      fake.engine(
        const ChunkAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          seq: 2,
          next: 2,
          status: ChunkStatus.gap,
        ),
      );
      await pumpEventQueue();

      expect(fake.sentOf<LogChunkFrame>().map((c) => c.seq), [2]);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('is not sent twice for a job that ended without a report', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      started.single.work.finish();
      await pumpEventQueue();

      // Nothing reported, so nothing waits for an acknowledgement.
      expect(started.single.outbox.awaitsAcknowledgement, isFalse);
      await offer(fake, 'job_2', leaseId: 'lse_2');
      await offer(fake, 'job_3', leaseId: 'lse_3');
      expect(fake.sentOf<LeaseRejectFrame>(), isEmpty);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });
  });

  group('cancel', () {
    test('stops the job and reports nothing more', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      fake.engine(
        const CancelFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          reason: 'The lease was lost.',
        ),
      );
      await pumpEventQueue();

      expect(started.single.work.cancelled, isTrue);
      expect(log.any((m) => m.contains('cancelled by the engine')), isTrue);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('stops a job of a lease the engine does not name', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      fake.engine(const CancelFrame(jobId: 'job_1', reason: 'Unknown lease.'));
      await pumpEventQueue();

      expect(started.single.work.cancelled, isTrue);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test(
      'ignores the cancel of another lease of the job, or of a stranger',
      () async {
        final fake = socket();
        final running = agent().run();
        await pumpEventQueue();
        await welcome(fake);
        await offer(fake, 'job_1');

        fake
          ..engine(
            const CancelFrame(
              jobId: 'job_1',
              leaseId: 'lse_old',
              reason: 'Old.',
            ),
          )
          ..engine(const CancelFrame(jobId: 'job_9', reason: 'Stranger.'));
        await pumpEventQueue();

        expect(started.single.work.cancelled, isFalse);
        await fake.engineCloses(runnerRevokedCloseCode);
        await running;
      },
    );
  });

  group('one-shot', () {
    test('takes one job, asks for no more and exits after it', () async {
      final fake = socket();
      final running = agent(oneShot: true).run();
      await pumpEventQueue();
      await welcome(fake);

      await offer(fake, 'job_1');

      expect(fake.sentOf<DrainFrame>().single.draining, isTrue);
      await offer(fake, 'job_2', leaseId: 'lse_2');
      expect(fake.sentOf<LeaseRejectFrame>().single.reason, 'draining');
      started.single.work.finish();
      started.single.outbox.finish(state: JobState.failed, message: 'no');
      fake.engine(
        const DoneAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          state: JobState.failed,
        ),
      );
      expect(await running, AgentExit.oneShotDone);
    });

    test('exits when the job is cancelled', () async {
      final fake = socket();
      final running = agent(oneShot: true).run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      fake.engine(const CancelFrame(jobId: 'job_1', reason: 'Cancelled.'));

      expect(await running, AgentExit.oneShotDone);
    });

    test('waits for a job that never comes', () async {
      final fake = socket();
      final agent0 = agent(oneShot: true);
      final running = agent0.run();
      await pumpEventQueue();
      await welcome(fake);

      expect(agent0.activeJobs, 0);
      agent0.drain();
      expect(await running, AgentExit.drained);
    });
  });

  group('drain', () {
    test('before the first connection ends the runner at once', () async {
      final agent0 = agent()
        ..drain()
        ..drain();

      expect(await agent0.run(), AgentExit.drained);
    });

    test('is announced with the hello of a reconnect', () async {
      final first = socket();
      final second = socket();
      final agent0 = agent();
      final running = agent0.run();
      await pumpEventQueue();
      await welcome(first);
      await offer(first, 'job_1');
      agent0.drain();
      await first.engineCloses();
      await pumpEventQueue();

      await welcome(second);

      expect(second.sentOf<HelloFrame>().single.draining, isTrue);
      started.single.work.finish();
      started.single.outbox.finish(state: JobState.succeeded);
      second.engine(
        const DoneAckFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          state: JobState.succeeded,
        ),
      );
      expect(await running, AgentExit.drained);
    });
  });

  group('the connection', () {
    test('is made again with a growing delay when it drops', () async {
      final first = socket();
      final second = socket();
      final third = socket();
      final running = agent().run();
      await pumpEventQueue();
      await first.engineCloses();
      await pumpEventQueue();
      await second.engineCloses(runnerTimeoutCloseCode);
      await pumpEventQueue();

      await welcome(third);
      expect(third.sentOf<HelloFrame>(), hasLength(1));
      await third.engineCloses(runnerRevokedCloseCode);
      await running;

      expect(waited, hasLength(2));
      expect(waited[0], lessThanOrEqualTo(const Duration(seconds: 1)));
      expect(waited[1], greaterThan(waited[0]));
      expect(log.where((m) => m.contains('connecting again')), hasLength(2));
    });

    test('starts the delay again after a connection that worked', () async {
      final first = socket();
      final second = socket();
      final third = socket();
      final running = agent().run();
      await pumpEventQueue();
      await first.engineCloses();
      await pumpEventQueue();
      await welcome(second);
      await second.engineCloses();
      await pumpEventQueue();

      await welcome(third);
      await third.engineCloses(runnerRevokedCloseCode);
      await running;

      expect(waited, hasLength(2));
      expect(waited[1], lessThanOrEqualTo(const Duration(seconds: 1)));
    });

    test('tries again when the engine cannot be reached', () async {
      connections
        ..add(const ConnectionException('refused'))
        ..add(Exception('socket'))
        ..add(const ApiException('Busy.', statusCode: 503));
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;

      expect(waited, hasLength(3));
      expect(log.first, 'Cannot connect: refused');
      expect(log[1], contains('Exception: socket'));
      expect(log[2], 'Cannot connect: Busy.');
    });

    test('keeps going after a connection that breaks', () async {
      final first = socket();
      final second = socket();
      final running = agent().run();
      await pumpEventQueue();
      first.breaks();
      await pumpEventQueue();

      await welcome(second);
      await second.engineCloses(runnerRevokedCloseCode);
      await running;

      expect(log.any((m) => m.contains('The connection broke')), isTrue);
    });

    test('is not made again when the credential is refused', () async {
      connections.add(
        const ApiException(
          'Missing, unknown or revoked bearer token.',
          statusCode: 401,
          code: ApiErrorCode.unauthorized,
        ),
      );

      expect(await agent().run(), AgentExit.credentialRejected);

      expect(log.single, contains('Pair it again'));
      expect(waited, isEmpty);
    });

    test('is not made again when the token is of another kind', () async {
      connections.add(
        const ApiException(
          'Not a runner.',
          statusCode: 403,
          code: ApiErrorCode.forbidden,
        ),
      );

      expect(await agent().run(), AgentExit.credentialRejected);
    });

    test('is not made again when the runner was revoked', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1');

      await fake.engineCloses(runnerRevokedCloseCode);

      expect(await running, AgentExit.revoked);
      expect(started.single.work.cancelled, isTrue);
      expect(log.any((m) => m.contains('revoked')), isTrue);
    });

    test('is not made again when another connection took over', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();

      await fake.engineCloses(runnerReplacedCloseCode);

      expect(await running, AgentExit.replaced);
    });

    test(
      'ends when the runner is stopped, and its jobs are cancelled',
      () async {
        final fake = socket();
        final agent0 = agent();
        final running = agent0.run();
        await pumpEventQueue();
        await welcome(fake);
        await offer(fake, 'job_1');

        await agent0.stop();

        expect(await running, AgentExit.stopped);
        expect(fake.closedByRunner, isTrue);
        expect(started.single.work.cancelled, isTrue);
      },
    );

    test('stops waiting to connect again when it is stopped', () async {
      final first = socket();
      final delayed = Completer<void>();
      final agent0 = agent(delay: (_) => delayed.future);
      final running = agent0.run();
      await pumpEventQueue();
      await first.engineCloses();
      await pumpEventQueue();

      await agent0.stop();

      expect(await running, AgentExit.stopped);
    });

    test('lets frames it cannot use pass', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);

      fake
        ..engineText('not json')
        ..engineText('[]')
        ..engineText(jsonEncode({'type': 'cancel'}))
        ..engineText(jsonEncode({'type': 'warp', 'speed': 9}))
        ..engine(const HeartbeatAckFrame())
        ..engine(const FaultFrame(code: 'invalid_frame', message: 'Bad.'));
      await pumpEventQueue();

      expect(log.where((m) => m.contains('not JSON')), hasLength(1));
      expect(log.any((m) => m.contains('cannot read')), isTrue);
      expect(log.any((m) => m.contains('(invalid_frame): Bad.')), isTrue);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('survives a connection that cannot be written to', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      fake.sendFails = true;

      await offer(fake, 'job_1');

      expect(started, hasLength(1));
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('says what it could not do with a frame', () async {
      final fake = socket();
      processes.handler = (call) => throw StateError('probe broke');
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);

      fake.engine(
        const ProbeFrame(
          probeId: 'prb_1',
          commands: [ProbeCommand(id: 'git', executable: 'git')],
        ),
      );
      await pumpEventQueue();

      expect(log.any((m) => m.contains('could not be handled')), isTrue);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });
  });

  group('secrets', () {
    test('are asked of the engine and handed to the job', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1', secrets: ['ks']);

      final value = started.single.requestSecret('ks');
      await pumpEventQueue();
      expect(fake.sentOf<SecretRequestFrame>().single.key, 'ks');
      fake.engine(
        SecretValueFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          key: 'ks',
          value: base64Encode([1, 2, 3]),
        ),
      );

      expect(await value, [1, 2, 3]);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('are denied, and the job gets nothing', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1', secrets: ['ks']);

      final value = started.single.requestSecret('ks');
      await pumpEventQueue();
      fake.engine(
        const SecretDeniedFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          key: 'ks',
          reason: 'Not yours.',
        ),
      );

      expect(await value, isNull);
      expect(log.any((m) => m.contains('Not yours.')), isTrue);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('are nothing when the value is not base64', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1', secrets: ['ks']);

      final value = started.single.requestSecret('ks');
      await pumpEventQueue();
      fake.engine(
        const SecretValueFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          key: 'ks',
          value: '!!not base64!!',
        ),
      );

      expect(await value, isNull);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('fail when the engine does not answer', () async {
      final fake = socket();
      final running = agent(secretTimeout: const Duration(milliseconds: 20))
          .run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1', secrets: ['ks']);

      await expectLater(
        started.single.requestSecret('ks'),
        throwsA(isA<TimeoutException>()),
      );
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('are asked again after a reconnect if the answer was lost', () async {
      final first = socket();
      final second = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(first);
      await offer(first, 'job_1', secrets: ['ks']);
      final value = started.single.requestSecret('ks');
      await pumpEventQueue();
      await first.engineCloses();
      await pumpEventQueue();

      await welcome(second);

      expect(second.sentOf<SecretRequestFrame>().single.key, 'ks');
      second.engine(
        SecretValueFrame(
          jobId: 'job_1',
          leaseId: 'lse_1',
          key: 'ks',
          value: base64Encode([9]),
        ),
      );
      expect(await value, [9]);
      await second.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test('that nobody asked for are ignored', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);

      fake
        ..engine(
          const SecretValueFrame(
            jobId: 'job_9',
            leaseId: 'lse_9',
            key: 'x',
            value: 'AQ==',
          ),
        )
        ..engine(
          const SecretDeniedFrame(
            jobId: 'job_9',
            leaseId: 'lse_9',
            key: 'x',
            reason: 'No.',
          ),
        );
      await pumpEventQueue();

      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });

    test(
      'that wait for the engine are given up when the runner stops',
      () async {
        final fake = socket();
        final agent0 = agent();
        final running = agent0.run();
        await pumpEventQueue();
        await welcome(fake);
        await offer(fake, 'job_1', secrets: ['ks']);
        final value = started.single.requestSecret('ks');
        await pumpEventQueue();

        await agent0.stop();

        expect(await value, isNull);
        expect(await running, AgentExit.stopped);
      },
    );

    test('that wait for a job that was cancelled are given up', () async {
      final fake = socket();
      final running = agent().run();
      await pumpEventQueue();
      await welcome(fake);
      await offer(fake, 'job_1', secrets: ['ks']);
      final value = started.single.requestSecret('ks');
      await pumpEventQueue();

      fake.engine(const CancelFrame(jobId: 'job_1', reason: 'Cancelled.'));

      expect(await value, isNull);
      await fake.engineCloses(runnerRevokedCloseCode);
      await running;
    });
  });
}

class _FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
