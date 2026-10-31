import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';
import '../../helpers/runner_harness.dart';

void main() {
  late RunnerHarness h;

  setUp(() async => h = await RunnerHarness.create());
  tearDown(() => expect(h.errors, isEmpty));

  Future<(FakeRunner, String)> leased({
    List<StepPlan>? steps,
    bool accept = true,
  }) async {
    final runner = await h.online();
    final jobId = await h.job(needs: ['ios-sign'], steps: steps);
    await h.scheduler.pump();
    if (accept) await runner.accept();
    return (runner, jobId);
  }

  List<String> logged(String jobId) => [
    for (final line in h.jobs.logStore.lines[jobId] ?? <LogLineFrame>[])
      '${line.seq}:${line.step}:${line.text}',
  ];

  group('log chunks', () {
    test('stores the next chunk and numbers the lines of the job', () async {
      final (runner, jobId) = await leased(steps: [h.script(), h.script()]);

      await runner.chunk(1, ['a', 'b']);
      await runner.chunk(2, ['c'], step: 1);

      expect(logged(jobId), ['1:0:a', '2:0:b', '3:1:c']);
      expect(runner.chunkAcks.map((a) => (a.seq, a.next, a.status)), [
        (1, 2, ChunkStatus.stored),
        (2, 3, ChunkStatus.stored),
      ]);
      expect(await h.jobs.logs.head(jobId), 3);
      final paths = (await h.steps(jobId)).map((s) => s.logPath);
      expect(paths, [
        '/logs/$jobId/0-scripted.log',
        '/logs/$jobId/1-scripted.log',
      ]);
    });

    test('a duplicate chunk is stored once', () async {
      final (runner, jobId) = await leased();

      await runner.chunk(1, ['a']);
      await runner.chunk(1, ['a']);
      await runner.chunk(1, ['something else']);
      await runner.chunk(2, ['b']);
      await runner.chunk(2, ['b']);

      expect(logged(jobId), ['1:0:a', '2:0:b']);
      expect(runner.chunkAcks.map((a) => (a.seq, a.next, a.status)), [
        (1, 2, ChunkStatus.stored),
        (1, 2, ChunkStatus.duplicate),
        (1, 2, ChunkStatus.duplicate),
        (2, 3, ChunkStatus.stored),
        (2, 3, ChunkStatus.duplicate),
      ]);
    });

    test(
      'a chunk out of order is a gap: nothing is stored until it fits',
      () async {
        final (runner, jobId) = await leased();

        await runner.chunk(2, ['b']);
        await runner.chunk(3, ['c']);
        expect(logged(jobId), isEmpty);
        await runner.chunk(1, ['a']);
        // The runner sends again from where the engine wants to go on.
        await runner.chunk(2, ['b']);
        await runner.chunk(3, ['c']);

        expect(logged(jobId), ['1:0:a', '2:0:b', '3:0:c']);
        expect(runner.chunkAcks.map((a) => (a.seq, a.next, a.status)), [
          (2, 1, ChunkStatus.gap),
          (3, 1, ChunkStatus.gap),
          (1, 2, ChunkStatus.stored),
          (2, 3, ChunkStatus.stored),
          (3, 4, ChunkStatus.stored),
        ]);
      },
    );

    test('masks what the engine knows to be secret', () async {
      final (runner, jobId) = await leased();
      h.jobs.masker.add('hunter2');

      await runner.chunk(1, ['password is hunter2', 'fine']);

      expect(logged(jobId), ['1:0:password is ***', '2:0:fine']);
    });

    test('drops lines of a step the job does not have', () async {
      final (runner, jobId) = await leased();

      await runner.chunk(1, ['a']);
      await runner.chunk(2, ['b'], step: 5);
      await runner.chunk(3, ['c'], step: -1);

      expect(logged(jobId), ['1:0:a']);
      expect(runner.chunkAcks.last.status, ChunkStatus.stored);
      expect(runner.chunkAcks.last.next, 4);
    });

    test('refuses a chunk that is too large', () async {
      final (runner, jobId) = await leased();

      await runner.chunk(1, List.filled(LogChunkFrame.maxLines + 1, 'x'));

      expect(runner.faults.single.code, 'chunk_too_large');
      expect(runner.chunkAcks, isEmpty);
      expect(logged(jobId), isEmpty);
      await runner.chunk(1, List.filled(LogChunkFrame.maxLines, 'x'));
      expect(runner.chunkAcks.single.status, ChunkStatus.stored);
    });

    test('a new lease numbers its chunks from 1 and the log goes on', () async {
      final (runner, jobId) = await leased();
      await runner.chunk(1, ['a', 'b']);
      h.clock.advance(const Duration(seconds: 90));
      await runner.heartbeat(const []);
      await h.hub.sweep();
      await h.settle();
      expect(runner.offers, hasLength(2));

      await runner.chunk(1, ['c'], lease: runner.leaseOf());

      expect(logged(jobId), ['1:0:a', '2:0:b', '3:0:c']);
    });

    test('are for the lease the runner holds', () async {
      final (runner, jobId) = await leased();
      final other = await h.online(name: 'other');

      await runner.chunk(1, [
        'a',
      ], lease: LeaseRef(jobId: jobId, leaseId: 'lse_wrong'));
      await other.chunk(1, ['a'], lease: runner.leaseOf());

      expect(logged(jobId), isEmpty);
      expect(runner.cancels, hasLength(1));
      expect(other.cancels, hasLength(1));
    });

    test('reach those who follow the job', () async {
      final (runner, jobId) = await leased();
      final seen = <int>[];
      final subscription = h.jobs.logs
          .follow(jobId)
          .listen(
            (event) => seen.add((event as FanOutItem<LogLineFrame>).value.seq),
          );
      await h.settle();

      await runner.chunk(1, ['a', 'b']);
      await h.settle();
      await runner.done(JobState.succeeded, lastChunk: 1);
      await h.settle();

      expect(seen, [1, 2]);
      await subscription.cancel();
    });
  });

  group('step states', () {
    test('are recorded with their result and times', () async {
      final (runner, jobId) = await leased();

      await runner.step(0, StepState.running);
      await runner.send(
        StepStateFrame(
          jobId: jobId,
          leaseId: runner.offer.leaseId,
          ordinal: 0,
          state: StepState.succeeded,
          attempts: 1,
          result: const {'artifact': 'a.ipa'},
          message: 'done',
          startedAt: DateTime.utc(2026, 10, 14, 8),
          finishedAt: DateTime.utc(2026, 10, 14, 9),
        ),
      );

      final step = (await h.steps(jobId)).single;
      expect(step.state, StepState.succeeded);
      expect(step.attempts, 1);
      expect(step.result, {'artifact': 'a.ipa'});
      expect(step.message, 'done');
      expect(step.startedAt, DateTime.utc(2026, 10, 14, 8));
      expect(step.finishedAt, DateTime.utc(2026, 10, 14, 9));
      expect(step.pgid, isNull);
      expect(
        [for (final event in await h.eventsOf<JobStepChanged>()) event.state],
        [StepState.running, StepState.succeeded],
      );
    });

    test('get the time of the engine when the runner gives none', () async {
      final (runner, jobId) = await leased();

      await runner.step(0, StepState.running);
      final started = h.clock.now();
      h.clock.advance(const Duration(seconds: 5));
      await runner.step(0, StepState.failed, message: 'boom');

      final step = (await h.steps(jobId)).single;
      expect(step.startedAt, started);
      expect(step.finishedAt, h.clock.now());
      expect(step.message, 'boom');
    });

    test('are idempotent and never go back', () async {
      final (runner, jobId) = await leased();

      await runner.step(0, StepState.running);
      await runner.step(0, StepState.running);
      await runner.step(0, StepState.succeeded);
      await runner.step(0, StepState.succeeded);
      // Late copies of what was said before change nothing.
      await runner.step(0, StepState.running);
      await runner.step(0, StepState.failed);
      await runner.step(0, StepState.pending);

      expect((await h.steps(jobId)).single.state, StepState.succeeded);
      expect(await h.eventsOf<JobStepChanged>(), hasLength(2));
    });

    test('a new attempt is newer than a finished one', () async {
      final (runner, jobId) = await leased();
      await runner.step(0, StepState.failed);

      await runner.step(0, StepState.running, attempts: 2);
      await runner.step(0, StepState.failed);

      final step = (await h.steps(jobId)).single;
      expect(step.state, StepState.running);
      expect(step.attempts, 2);
    });

    test('mask what the engine knows to be secret', () async {
      final (runner, jobId) = await leased();
      h.jobs.masker.add('hunter2');

      await runner.step(0, StepState.failed, message: 'bad: hunter2');

      expect((await h.steps(jobId)).single.message, 'bad: ***');
    });

    test('of a step the job does not have are a fault', () async {
      final (runner, _) = await leased();

      await runner.step(3, StepState.running);
      await runner.step(-1, StepState.running);

      expect(runner.faults, hasLength(2));
      expect(runner.faults.first.code, 'invalid_frame');
    });

    test('of a lease that is not held are cancelled', () async {
      final (runner, jobId) = await leased();

      await runner.step(
        0,
        StepState.running,
        lease: LeaseRef(jobId: jobId, leaseId: 'lse_wrong'),
      );

      expect(runner.cancels, hasLength(1));
      expect((await h.steps(jobId)).single.state, StepState.pending);
    });
  });

  group('job done', () {
    test('ends the job, frees the slot and answers', () async {
      final (runner, jobId) = await leased();
      final next = await h.job(needs: ['ios-sign']);
      await runner.step(0, StepState.succeeded);
      final lease = runner.leaseOf();

      await runner.done(JobState.succeeded);
      await h.settle();

      final job = await h.record(jobId);
      expect(job.state, JobState.succeeded);
      expect(job.leaseUntil, isNull);
      expect(job.runnerId, runner.id);
      expect(job.message, isNull);
      expect(job.finishedAt, h.clock.now());
      expect(
        runner.link.sentOf<DoneAckFrame>().single,
        DoneAckFrame(
          jobId: jobId,
          leaseId: lease.leaseId,
          state: JobState.succeeded,
        ),
      );
      expect(h.hub.holdsLease(runner.id, jobId, lease.leaseId), isFalse);
      // The next job takes the place.
      expect(runner.offer.jobId, next);
      expect(await h.state(next), JobState.running);
      expect(h.hub.jobsOf(runner.id), [next]);
    });

    test('is answered again when it arrives twice', () async {
      final (runner, jobId) = await leased();
      await runner.step(0, StepState.succeeded);

      await runner.done(JobState.succeeded);
      final events = (await h.events()).length;
      await runner.done(JobState.succeeded);
      await runner.done(JobState.failed, message: 'a late opinion');

      expect(runner.link.sentOf<DoneAckFrame>().map((a) => a.state), [
        JobState.succeeded,
        JobState.succeeded,
        JobState.succeeded,
      ]);
      expect((await h.record(jobId)).state, JobState.succeeded);
      expect((await h.events()).length, events);
    });

    test('is not believed when a step is not done', () async {
      final (runner, jobId) = await leased(steps: [h.script(), h.script()]);
      await runner.step(0, StepState.succeeded);
      await runner.step(1, StepState.running);

      await runner.done(JobState.succeeded);

      final job = await h.record(jobId);
      expect(job.state, JobState.failed);
      expect(
        job.message,
        'The runner reported the job done, but step 1 (scripted) is running.',
      );
      expect(runner.link.sentOf<DoneAckFrame>().single.state, JobState.failed);
      // The step that never reported again is not left running.
      final step = (await h.steps(jobId))[1];
      expect(step.state, StepState.failed);
      expect(step.message, contains('without a report'));
    });

    test('a failure carries the message, masked', () async {
      final (runner, jobId) = await leased();
      h.jobs.masker.add('hunter2');
      await runner.step(0, StepState.failed, message: 'hunter2 failed');

      await runner.done(JobState.failed, message: 'build failed (hunter2)');

      final job = await h.record(jobId);
      expect(job.state, JobState.failed);
      expect(job.message, 'build failed (***)');
    });

    test('a failure without a message names the step that failed', () async {
      final (runner, jobId) = await leased();
      await runner.step(0, StepState.failed, message: 'exit 65');

      await runner.done(JobState.failed);

      expect(
        (await h.record(jobId)).message,
        'Step 0 (scripted) failed: exit 65',
      );
    });

    test('a failure without anything to say still says so', () async {
      final (runner, jobId) = await leased();

      await runner.done(JobState.failed);

      expect(
        (await h.record(jobId)).message,
        'The runner reported the job failed.',
      );
    });

    test('a cancelled job cancels its running step', () async {
      final (runner, jobId) = await leased();
      await runner.step(0, StepState.running);

      await runner.done(JobState.cancelled, message: 'on request');

      final job = await h.record(jobId);
      expect(job.state, JobState.cancelled);
      expect(job.message, 'on request');
      final step = (await h.steps(jobId)).single;
      expect(step.state, StepState.cancelled);
      expect(step.message, isNull);
    });

    test('waits for the log it has not got', () async {
      final (runner, jobId) = await leased();
      await runner.step(0, StepState.succeeded);
      await runner.chunk(1, ['a']);

      await runner.done(JobState.succeeded, lastChunk: 2);

      expect((await h.record(jobId)).state, JobState.running);
      expect(runner.link.sentOf<DoneAckFrame>(), isEmpty);
      expect(
        runner.chunkAcks.last,
        ChunkAckFrame(
          jobId: jobId,
          leaseId: runner.offer.leaseId,
          seq: 2,
          next: 2,
          status: ChunkStatus.gap,
        ),
      );
      await runner.chunk(2, ['b']);
      await runner.done(JobState.succeeded, lastChunk: 2);
      expect((await h.record(jobId)).state, JobState.succeeded);
      expect(logged(jobId), ['1:0:a', '2:0:b']);
    });

    test('for a lease that is not held is cancelled', () async {
      final (runner, jobId) = await leased();
      final other = await h.online(name: 'other');

      await runner.done(
        JobState.succeeded,
        lease: LeaseRef(jobId: jobId, leaseId: 'lse_wrong'),
      );
      await other.done(JobState.succeeded, lease: runner.leaseOf());

      expect(runner.cancels, hasLength(1));
      expect(other.cancels, hasLength(1));
      expect((await h.record(jobId)).state, JobState.running);
    });

    test('forgets old reports, but not recent ones', () async {
      final (runner, _) = await leased();
      await runner.step(0, StepState.succeeded);
      await runner.done(JobState.succeeded);

      for (var i = 0; i < 520; i++) {
        final job = await h.job(needs: ['ios-sign']);
        await h.scheduler.pump();
        await runner.step(0, StepState.succeeded);
        await runner.done(JobState.succeeded);
        expect(await h.state(job), JobState.succeeded);
      }

      // The first report is forgotten: a copy of it is not a lease any more.
      await runner.done(
        JobState.succeeded,
        lease: runner.leaseOf(runner.offers.first),
      );
      expect(runner.cancels, hasLength(1));
      await runner.done(JobState.succeeded);
      expect(runner.link.sentOf<DoneAckFrame>().length, 522);
    });
  });

  group('secrets (D-09)', () {
    const keystoreInput = {
      'secretFiles': {'XPATH_KEYSTORE_FILE': 'ks'},
      'secretEnvironment': {
        'XPATH_KEYSTORE_STORE_PASSWORD': 'ks.storePassword',
        'XPATH_KEYSTORE_KEY_PASSWORD': 'ks.keyPassword',
        'TOKEN': 'github',
      },
    };

    Future<(FakeRunner, String)> signing() async {
      await h.credentials.put(
        const AssignedCredential(
          flavor: CredentialFlavor(
            id: 'flv_1',
            projectId: 'prj_1',
            appPath: '.',
            name: 'prod',
          ),
          credential: CredentialRecord(
            id: 'crd_1',
            name: 'crd_1',
            kind: CredentialKind.keystore,
            secretKey: 'ks',
          ),
        ),
      );
      await h.secrets.writeBytes('ks', [0xff, 0xfe, 0x00, 0x01]);
      await h.secrets.write('ks.storePassword', 'store-pw');
      await h.secrets.write('ks.keyPassword', 'key-pw');
      await h.secrets.write('github', 'ghp_token');
      await h.secrets.write('unrelated', 'x');
      return await leased(
        steps: [
          const StepPlan(
            kind: 'scripted',
            input: keystoreInput,
            sideEffect: false,
          ),
        ],
      );
    }

    test('only the signing material the steps name is offered', () async {
      final (runner, _) = await signing();

      expect(runner.offer.secrets, [
        'ks',
        'ks.keyPassword',
        'ks.storePassword',
      ]);
    });

    test('is given once per lease, as bytes, and masked afterwards', () async {
      final (runner, jobId) = await signing();

      await runner.secret('ks.storePassword');
      await runner.secret('ks');
      await runner.secret('ks.storePassword');

      final values = runner.link.sentOf<SecretValueFrame>();
      expect(values.map((v) => v.key), ['ks.storePassword', 'ks']);
      expect(utf8.decode(base64Decode(values[0].value)), 'store-pw');
      expect(base64Decode(values[1].value), [0xff, 0xfe, 0x00, 0x01]);
      expect(
        runner.link.sentOf<SecretDeniedFrame>().single.reason,
        contains('already'),
      );
      expect(await h.eventsOf<RunnerSecretDelivered>(), [
        RunnerSecretDelivered(
          runnerId: runner.id,
          jobId: jobId,
          key: 'ks.storePassword',
        ),
        RunnerSecretDelivered(runnerId: runner.id, jobId: jobId, key: 'ks'),
      ]);
      // The password is masked in what comes back; the binary is not text.
      expect(h.jobs.masker.secrets, ['store-pw']);
      await runner.chunk(1, ['password store-pw']);
      expect(logged(jobId), ['1:0:password ***']);
    });

    test('gives the Shorebird key of a step once, masked (ADR 0012)', () async {
      await h.credentials.put(
        const AssignedCredential(
          flavor: CredentialFlavor(
            id: 'flv_1',
            projectId: 'prj_1',
            appPath: '.',
            name: 'prod',
          ),
          credential: CredentialRecord(
            id: 'crd_2',
            name: 'crd_2',
            kind: CredentialKind.shorebird,
            secretKey: 'sb',
          ),
        ),
      );
      await h.secrets.write('sb', 'sb_api_secret');
      final (runner, jobId) = await leased(
        steps: [
          const StepPlan(
            kind: 'shorebird.release',
            input: {'tokenSecret': 'sb'},
            sideEffect: true,
          ),
        ],
      );

      expect(runner.offer.secrets, ['sb']);
      await runner.secret('sb');
      await runner.secret('sb');

      final values = runner.link.sentOf<SecretValueFrame>();
      expect(utf8.decode(base64Decode(values.single.value)), 'sb_api_secret');
      expect(
        runner.link.sentOf<SecretDeniedFrame>().single.reason,
        contains('already'),
      );
      expect(await h.eventsOf<RunnerSecretDelivered>(), [
        RunnerSecretDelivered(runnerId: runner.id, jobId: jobId, key: 'sb'),
      ]);
      expect(h.jobs.masker.secrets, ['sb_api_secret']);
    });

    test('gives the define file a build names and masks each value', () async {
      await h.credentials.put(
        const AssignedCredential(
          flavor: CredentialFlavor(
            id: 'flv_1',
            projectId: 'prj_1',
            appPath: '.',
            name: 'prod',
          ),
          credential: CredentialRecord(
            id: 'crd_3',
            name: 'crd_3',
            kind: CredentialKind.dartDefines,
            secretKey: 'defines',
          ),
        ),
      );
      const text = '{"API_KEY": "k-12345"}';
      await h.secrets.write('defines', text);
      final (runner, _) = await leased(
        steps: [
          const StepPlan(
            kind: 'build.android',
            input: {'dartDefineSecret': 'defines'},
            sideEffect: false,
          ),
        ],
      );

      expect(runner.offer.secrets, ['defines']);
      await runner.secret('defines');

      expect(
        utf8.decode(
          base64Decode(runner.link.sentOf<SecretValueFrame>().single.value),
        ),
        text,
      );
      expect(h.jobs.masker.secrets, [
        text,
        'k-12345',
        base64.encode(utf8.encode('API_KEY=k-12345')),
      ]);
    });

    test('gives a Linux build the identity and the profile the engine makes '
        '(ADR 0014)', () async {
      const flavor = CredentialFlavor(
        id: 'flv_1',
        projectId: 'prj_1',
        appPath: '.',
        name: 'prod',
        iosBundleId: 'com.mataa.app',
      );
      for (final kind in [
        CredentialKind.appleDistribution,
        CredentialKind.ascKey,
      ]) {
        await h.credentials.put(
          AssignedCredential(
            flavor: flavor,
            credential: CredentialRecord(
              id: 'crd_${kind.wire}',
              name: kind.wire,
              kind: kind,
              secretKey: kind.wire,
            ),
          ),
        );
        await CredentialMaterial.fromFields(
          kind,
          credentialFields(kind),
        ).write(h.secrets, kind.wire);
      }
      h.asc
        ..certificates.add(
          const AscCertificate(id: 'cert-1', serialNumber: 'A1B2C3D4E5F'),
        )
        ..bundleIds['com.mataa.app'] = 'bundle-1';
      final profile = AppStoreProfiles.keyFor(
        'apple_distribution',
        'com.mataa.app',
      );
      final (runner, _) = await leased(
        steps: [
          StepPlan(
            kind: 'build.ios',
            input: {
              'linuxSigning': {
                'ASC_SIGNING_KEY': 'apple_distribution',
                'ASC_SIGNING_CERT': 'apple_distribution.certificate',
                'ASC_PROFILE': profile,
              },
            },
            sideEffect: false,
          ),
        ],
      );

      expect(runner.offer.secrets, [
        'apple_distribution',
        'apple_distribution.certificate',
        profile,
      ]);
      h.asc.failure = const AscServerException(503, 'down');
      // A profile is answered aside, so the frames behind it go on.
      await runner.secret(profile);
      await pumpEventQueue();
      await runner.secret(profile);
      await pumpEventQueue();
      await runner.secret('apple_distribution');

      expect(
        runner.link.sentOf<SecretDeniedFrame>().single.reason,
        'App Store Connect could not make the profile of com.mataa.app: down',
      );
      final values = runner.link.sentOf<SecretValueFrame>();
      expect(values.map((v) => v.key), [profile, 'apple_distribution']);
      expect(
        utf8.decode(base64Decode(values.first.value)),
        startsWith('profile XPath com.mataa.app A1B2C3D4E5F'),
      );
      expect(h.jobs.masker.secrets, contains(testSigningKey));
    });

    test('is never given for anything else', () async {
      final (runner, _) = await signing();

      await runner.secret('github');
      await runner.secret('unrelated');
      await runner.secret('nothing');

      expect(runner.link.sentOf<SecretValueFrame>(), isEmpty);
      expect(runner.link.sentOf<SecretDeniedFrame>().map((d) => d.key), [
        'github',
        'unrelated',
        'nothing',
      ]);
      expect(
        runner.link.sentOf<SecretDeniedFrame>().first.reason,
        contains('not signing material'),
      );
      expect(await h.eventsOf<RunnerSecretDelivered>(), isEmpty);
      expect(h.jobs.masker.secrets, isEmpty);
    });

    test(
      'is denied when there is no such secret or no way to read it',
      () async {
        final (runner, _) = await signing();
        await h.secrets.delete('ks.keyPassword');

        await runner.secret('ks.keyPassword');
        h.secrets.failure = const SecretsLockedException('locked');
        await runner.secret('ks.storePassword');
        h.secrets.failure = null;
        await runner.secret('ks.storePassword');

        final denied = runner.link.sentOf<SecretDeniedFrame>();
        expect(denied.map((d) => d.reason), [
          'There is no such secret.',
          'The engine cannot read its secrets right now.',
        ]);
        // The refusal did not use up the one delivery.
        expect(
          runner.link.sentOf<SecretValueFrame>().single.key,
          'ks.storePassword',
        );
      },
    );

    test('is not given for a lease the runner does not hold', () async {
      final (runner, jobId) = await signing();

      await runner.secret(
        'ks',
        lease: LeaseRef(jobId: jobId, leaseId: 'lse_wrong'),
      );
      await runner.done(JobState.failed);
      await runner.secret(
        'ks',
        lease: LeaseRef(jobId: jobId, leaseId: runner.offer.leaseId),
      );

      expect(runner.link.sentOf<SecretValueFrame>(), isEmpty);
      expect(runner.cancels, hasLength(2));
    });

    test('a job that names no secret is offered none', () async {
      final (runner, _) = await leased();

      expect(runner.offer.secrets, isEmpty);
    });
  });
}
