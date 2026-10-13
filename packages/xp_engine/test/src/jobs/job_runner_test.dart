import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/job_harness.dart';

/// A process that prints [text] and then runs until it is cancelled.
FakeSupervisedHandler _hangs(Completer<void> started, [String text = 'up']) =>
    (process) async {
      await process.emit(text);
      started.complete();
      await Completer<void>().future;
      return 0;
    };

void main() {
  late JobHarness harness;

  setUp(() => harness = JobHarness.create());

  group('create', () {
    test('stores a queued job with a pending step per plan', () async {
      final job = await harness.create([
        harness.command('flutter', arguments: ['build']),
        harness.command('git', sideEffect: true),
      ]);

      expect(job.id, startsWith('job_'));
      expect(job.state, JobState.queued);
      expect(job.projectId, 'prj_1');
      expect(job.workflowVersionId, 'wfv_1');
      expect(job.sha, 'a' * 40);
      expect(job.createdAt, DateTime.utc(2026, 10, 13, 9));
      expect(job.steps.map((s) => (s.ordinal, s.kind, s.sideEffect, s.state)), [
        (0, 'command', false, StepState.pending),
        (1, 'command', true, StepState.pending),
      ]);
      expect(await harness.jobEvents(), ['job queued']);
    });

    test('gives every job its own id', () async {
      final first = await harness.create([]);
      final second = await harness.create([]);

      expect(first.id, isNot(second.id));
    });
  });

  group('get', () {
    test('returns the job with its steps', () async {
      final created = await harness.create([harness.command('x')]);

      expect(await harness.runner.get(created.id), created);
    });

    test('throws for an unknown job', () async {
      await expectLater(
        harness.runner.get('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });
  });

  group('start', () {
    test('runs the steps in order and succeeds', () async {
      harness.supervisor.handler = (process) async {
        await process.emit('hello from ${process.spec.executable}');
        return 0;
      };

      final job = await harness.run([
        harness.command('one'),
        harness.command('two'),
      ]);

      expect(job.state, JobState.succeeded);
      expect(job.message, isNull);
      expect(job.startedAt, isNotNull);
      expect(job.finishedAt, isNotNull);
      expect(
        job.steps.map((s) => (s.state, s.attempts, s.result?['exitCode'])),
        [(StepState.succeeded, 1, 0), (StepState.succeeded, 1, 0)],
      );
      expect(harness.supervisor.specs.map((s) => s.executable), ['one', 'two']);
      expect(await harness.jobEvents(), [
        'job queued',
        'job running',
        'step 0 running',
        'step 0 succeeded',
        'step 1 running',
        'step 1 succeeded',
        'job succeeded',
      ]);
    });

    test('returns the job running, before its steps are done', () async {
      final started = Completer<void>();
      harness.supervisor.handler = _hangs(started);
      final created = await harness.create([harness.command('x')]);

      final job = await harness.runner.start(created.id);

      expect(job.state, JobState.running);
      expect(harness.runner.activeJobs, [created.id]);
      await started.future;
      await harness.runner.cancel(created.id);
    });

    test('numbers the log lines across the steps of the job', () async {
      harness.supervisor.handler = (process) async {
        await process.emit('${process.spec.executable} 1');
        await process.emit('${process.spec.executable} 2');
        return 0;
      };

      final job = await harness.run([
        harness.command('a'),
        harness.command('b'),
      ]);

      expect(harness.logLines(job.id), ['0:a 1', '0:a 2', '1:b 1', '1:b 2']);
      expect(harness.logStore.lines[job.id]!.map((line) => line.seq), [
        1,
        2,
        3,
        4,
      ]);
      expect(harness.logStore.paths, [
        '/logs/${job.id}/0-command.log',
        '/logs/${job.id}/1-command.log',
      ]);
    });

    test('stops at the first failed step', () async {
      harness.supervisor.handler = (process) =>
          process.spec.executable == 'bad' ? 7 : 0;

      final job = await harness.run([
        harness.command('good'),
        harness.command('bad'),
        harness.command('never'),
      ]);

      expect(job.state, JobState.failed);
      expect(job.message, 'Step 1 (command) failed: bad exited with code 7.');
      expect(job.steps.map((s) => s.state), [
        StepState.succeeded,
        StepState.failed,
        StepState.pending,
      ]);
      expect(harness.supervisor.specs, hasLength(2));
    });

    test('rejects a job that is not queued, or unknown', () async {
      final job = await harness.run([harness.command('x')]);

      await expectLater(
        harness.runner.start(job.id),
        throwsA(isA<JobStateException>()),
      );
      await expectLater(
        harness.runner.start('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });

    test('keeps the machine awake while the job runs', () async {
      final started = Completer<void>();
      harness.supervisor.handler = _hangs(started);
      final created = await harness.create([harness.command('x')]);

      await harness.runner.start(created.id);
      await started.future;
      expect((harness.power.holds, harness.power.releases), (1, 0));

      await harness.runner.cancel(created.id);
      expect((harness.power.holds, harness.power.releases), (1, 1));
    });

    test('finishes a job without steps', () async {
      final job = await harness.run([]);

      expect(job.state, JobState.succeeded);
    });
  });

  group('process', () {
    test('gets only the allowed environment and the declared extras', () async {
      await harness.run([
        harness.command(
          'tool',
          environment: {'CI': 'true'},
          passThrough: ['GITHUB_TOKEN'],
        ),
      ]);

      expect(harness.supervisor.specs.single.environment, {
        'PATH': '/usr/bin',
        'HOME': '/home/me',
        'GITHUB_TOKEN': 'ghp_must_not_leak',
        'CI': 'true',
      });
    });

    test('does not get the host environment it did not ask for', () async {
      await harness.run([harness.command('tool')]);

      expect(
        harness.supervisor.specs.single.environment,
        isNot(contains('GITHUB_TOKEN')),
      );
    });

    test('runs in the working directory the command names', () async {
      await harness.run([
        StepPlan.of(
          const CommandStep(),
          const CommandInput(ProcessCommand('x', workingDirectory: '/work')),
        ),
      ]);

      expect(harness.supervisor.specs.single.workingDirectory, '/work');
    });

    test(
      'passes secrets by environment variable and by file, never in argv',
      () async {
        harness.secrets.values['asc.key'] = 'SECRET-TOKEN-VALUE';
        harness.secrets.values['play.sa'] =
            '{"private_key":"PRIVATE-KEY-BODY"}';

        final job = await harness.run([
          harness.command(
            'upload',
            arguments: ['--verbose', '--key-id', 'ABC'],
            secretEnvironment: {'ASC_TOKEN': 'asc.key'},
            secretFiles: {'PLAY_SA_FILE': 'play.sa'},
          ),
        ]);

        expect(job.state, JobState.succeeded);
        final spec = harness.supervisor.specs.single;
        expect(spec.environment['ASC_TOKEN'], 'SECRET-TOKEN-VALUE');
        expect(
          spec.environment['PLAY_SA_FILE'],
          '/secrets/${job.id}/0-PLAY_SA_FILE',
        );
        expect(
          harness.secretFiles.written['/secrets/${job.id}/0-PLAY_SA_FILE'],
          '{"private_key":"PRIVATE-KEY-BODY"}',
        );
        for (final argument in [spec.executable, ...spec.arguments]) {
          expect(argument, isNot(contains('SECRET-TOKEN-VALUE')));
          expect(argument, isNot(contains('PRIVATE-KEY-BODY')));
        }
        expect(spec.arguments, ['--verbose', '--key-id', 'ABC']);
      },
    );

    test('tells the masker about every secret before it starts', () async {
      harness.secrets.values['a'] = 'secret-a';
      harness.secrets.values['b'] = 'secret-b';

      await harness.run([
        harness.command(
          'tool',
          secretEnvironment: {'A': 'a'},
          secretFiles: {'B': 'b'},
        ),
      ]);

      expect(harness.masker.secrets, ['secret-a', 'secret-b']);
    });

    test('deletes the secret files when the job ends', () async {
      harness.secrets.values['k'] = 'secret-value';

      final job = await harness.run([
        harness.command('tool', secretFiles: {'K': 'k'}),
      ]);

      expect(harness.secretFiles.deleted, [job.id]);
      expect(harness.secretFiles.files, isEmpty);
    });

    test('fails the step when a secret does not exist', () async {
      final job = await harness.run([
        harness.command('tool', secretEnvironment: {'A': 'missing'}),
      ]);

      expect(job.state, JobState.failed);
      expect(
        job.steps.single.message,
        'SecretStoreException: There is no secret "missing".',
      );
      expect(harness.supervisor.specs, isEmpty);
    });

    test('fails the step when a secret variable has a bad name', () async {
      harness.secrets.values['k'] = 'secret-value';

      final job = await harness.run([
        harness.command('tool', secretEnvironment: {'BAD-NAME': 'k'}),
      ]);

      expect(job.steps.single.state, StepState.failed);
      expect(job.steps.single.message, contains('BAD-NAME'));
      expect(harness.supervisor.specs, isEmpty);
    });

    test('fails the step when the program cannot be started', () async {
      harness.supervisor.startError = const ProcessStartException(
        'tool',
        'not found',
      );

      final job = await harness.run([harness.command('tool')]);

      expect(job.steps.single.state, StepState.failed);
      expect(job.steps.single.message, contains('not found'));
    });

    test('records the process group while the step runs', () async {
      final started = Completer<void>();
      harness.supervisor.handler = _hangs(started);
      final created = await harness.create([harness.command('x')]);

      await harness.runner.start(created.id);
      await started.future;
      final running = (await harness.jobs.steps(created.id)).single;

      expect(running.pgid, 4000);
      expect(running.logPath, '/logs/${created.id}/0-command.log');

      await harness.runner.cancel(created.id);
      expect((await harness.jobs.steps(created.id)).single.pgid, isNull);
    });
  });

  group('cancel', () {
    test('stops the process and ends the job cancelled', () async {
      final started = Completer<void>();
      harness.supervisor.handler = _hangs(started);
      final created = await harness.create([
        harness.command('long'),
        harness.command('after'),
      ]);
      await harness.runner.start(created.id);
      await started.future;

      final job = await harness.runner.cancel(created.id);

      expect(harness.supervisor.processes.single.wasCancelled, isTrue);
      expect(job.state, JobState.cancelled);
      expect(job.message, 'Cancelled.');
      expect(job.steps.map((s) => s.state), [
        StepState.cancelled,
        StepState.pending,
      ]);
      expect(harness.runner.activeJobs, isEmpty);
    });

    test('lets a step that is not running a process stop at once', () async {
      final release = Completer<void>();
      final inside = Completer<void>();
      final scripted = ScriptedStep(
        onRun: (input, context) async {
          inside.complete();
          await release.future;
          final exit = await context.run(const ProcessCommand('late'));
          if (exit.cancelled) return const StepFailed('cancelled');
          return const StepSucceeded({});
        },
      );
      harness = JobHarness.create(scripted: scripted);
      final created = await harness.create([harness.script()]);
      await harness.runner.start(created.id);
      await inside.future;

      final cancelling = harness.runner.cancel(created.id);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      final job = await cancelling;

      expect(job.state, JobState.cancelled);
      expect(job.steps.single.state, StepState.cancelled);
      expect(harness.supervisor.specs, isEmpty, reason: 'nothing was started');
    });

    test('cancels a process that was started while the cancel came', () async {
      final gate = Completer<void>();
      harness.supervisor
        ..startGate = gate.future
        ..handler = (process) async {
          await Completer<void>().future;
          return 0;
        };
      final created = await harness.create([harness.command('long')]);
      await harness.runner.start(created.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final cancelling = harness.runner.cancel(created.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      final job = await cancelling;

      expect(harness.supervisor.processes.single.wasCancelled, isTrue);
      expect(job.state, JobState.cancelled);
      expect(job.steps.single.state, StepState.cancelled);
    });

    test('leaves a job succeeded whose last step finished anyway', () async {
      final inside = Completer<void>();
      final release = Completer<void>();
      final scripted = ScriptedStep(
        onRun: (input, context) async {
          inside.complete();
          await release.future;
          return const StepSucceeded({'ran': true});
        },
      );
      harness = JobHarness.create(scripted: scripted);
      final created = await harness.create([harness.script()]);
      await harness.runner.start(created.id);
      await inside.future;

      final cancelling = harness.runner.cancel(created.id);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      final job = await cancelling;

      expect(job.state, JobState.succeeded);
      expect(job.steps.single.state, StepState.succeeded);
    });

    test('ends a queued job at once', () async {
      final created = await harness.create([harness.command('x')]);

      final job = await harness.runner.cancel(created.id);

      expect(job.state, JobState.cancelled);
      expect(job.finishedAt, isNotNull);
      expect(job.steps.single.state, StepState.pending);
    });

    test(
      'ends a job that waits for a resume, and its interrupted step',
      () async {
        final created = await harness.create([harness.command('x')]);
        await harness.jobs.updateJob(
          (await harness.jobs.get(created.id))!
              .copyWith(state: JobState.waitingForResume),
        );
        await harness.jobs.updateStep(
          (await harness.jobs.steps(created.id)).single
              .copyWith(state: StepState.interrupted),
        );

        final job = await harness.runner.cancel(created.id);

        expect(job.state, JobState.cancelled);
        expect(job.steps.single.state, StepState.cancelled);
      },
    );

    test('rejects a job that ended, or unknown', () async {
      final job = await harness.run([harness.command('x')]);

      await expectLater(
        harness.runner.cancel(job.id),
        throwsA(isA<JobStateException>()),
      );
      await expectLater(
        harness.runner.cancel('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });
  });

  group('resume', () {
    Future<Job> failedJob() async {
      harness.supervisor.handler = (process) =>
          process.spec.executable == 'bad' ? 1 : 0;
      return await harness.run([
        harness.command('good'),
        harness.command('bad'),
        harness.command('after'),
      ]);
    }

    test(
      'skips the steps that are done and re-runs the one that failed',
      () async {
        final failed = await failedJob();
        harness.supervisor.handler = (process) => 0;
        final specsBefore = harness.supervisor.specs.length;

        final running = await harness.runner.resume(failed.id);
        final job = await harness.runner.whenFinished(failed.id);

        expect(running.state, JobState.running);
        expect(job.state, JobState.succeeded);
        expect(
          harness.supervisor.specs.skip(specsBefore).map((s) => s.executable),
          ['bad', 'after'],
        );
        expect(job.steps.map((s) => (s.state, s.attempts)), [
          (StepState.succeeded, 1),
          (StepState.succeeded, 2),
          (StepState.succeeded, 1),
        ]);
        expect(job.message, isNull);
      },
    );

    test('resumes a cancelled job', () async {
      final created = await harness.create([harness.command('x')]);
      await harness.runner.cancel(created.id);

      await harness.runner.resume(created.id);
      final job = await harness.runner.whenFinished(created.id);

      expect(job.state, JobState.succeeded);
    });

    test('with fromStep resets the steps from there on', () async {
      final failed = await failedJob();
      harness.supervisor.handler = (process) => 0;
      final specsBefore = harness.supervisor.specs.length;

      await harness.runner.resume(failed.id, fromStep: 0);
      final job = await harness.runner.whenFinished(failed.id);

      expect(
        harness.supervisor.specs.skip(specsBefore).map((s) => s.executable),
        ['good', 'bad', 'after'],
      );
      expect(job.steps.map((s) => s.attempts), [2, 2, 1]);
    });

    test('rejects a step that is not in the job', () async {
      final failed = await failedJob();

      for (final step in [-1, 3]) {
        await expectLater(
          harness.runner.resume(failed.id, fromStep: step),
          throwsA(isA<JobInvalidException>()),
        );
      }
    });

    test('rejects a step after one that is not done', () async {
      final failed = await failedJob();

      await expectLater(
        harness.runner.resume(failed.id, fromStep: 2),
        throwsA(
          isA<JobInvalidException>().having(
            (e) => e.message,
            'message',
            contains('Step 1 is failed'),
          ),
        ),
      );
    });

    test('rejects a job that is queued, succeeded or running', () async {
      final queued = await harness.create([harness.command('x')]);
      final done = await harness.run([harness.command('x')]);
      final started = Completer<void>();
      harness.supervisor.handler = _hangs(started);
      final running = await harness.create([harness.command('long')]);
      await harness.runner.start(running.id);
      await started.future;

      for (final id in [queued.id, done.id, running.id]) {
        await expectLater(
          harness.runner.resume(id),
          throwsA(isA<JobStateException>()),
          reason: id,
        );
      }
      await harness.runner.cancel(running.id);
    });

    test('rejects an unknown job', () async {
      await expectLater(
        harness.runner.resume('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });

    test('finishes a job whose steps are all done', () async {
      final done = await harness.run([harness.command('x')]);
      await harness.jobs.updateJob(
        (await harness.jobs.get(done.id))!
            .copyWith(state: JobState.interrupted),
      );

      await harness.runner.resume(done.id);
      final job = await harness.runner.whenFinished(done.id);

      expect(job.state, JobState.succeeded);
      expect(harness.supervisor.specs, hasLength(1));
    });
  });

  group('steps with side effects', () {
    test('are not checked on their first attempt', () async {
      await harness.run([harness.script(sideEffect: true)]);

      expect(harness.scripted.checks, isEmpty);
      expect(harness.scripted.runs, hasLength(1));
    });

    test('ask whether the work exists before they run again', () async {
      var attempt = 0;
      final scripted = ScriptedStep(
        onRun: (input, context) async {
          if (++attempt == 1) return const StepFailed('network');
          return const StepSucceeded({'ran': true});
        },
      );
      harness = JobHarness.create(scripted: scripted);
      final failed = await harness.run([harness.script(sideEffect: true)]);

      await harness.runner.resume(failed.id);
      final job = await harness.runner.whenFinished(failed.id);

      expect(scripted.checks, hasLength(1));
      expect(scripted.runs, hasLength(2));
      expect(job.steps.single.state, StepState.succeeded);
    });

    test('are skipped, with the result, when the work exists', () async {
      final scripted = ScriptedStep(
        onRun: (input, context) async => const StepFailed('lost the answer'),
        onAlreadyDone: (input, context) async => {'build': 42},
      );
      harness = JobHarness.create(scripted: scripted);
      final failed = await harness.run([
        harness.script(sideEffect: true),
        harness.command('after'),
      ]);

      await harness.runner.resume(failed.id);
      final job = await harness.runner.whenFinished(failed.id);

      expect(scripted.runs, hasLength(1), reason: 'not run again');
      expect(job.state, JobState.succeeded);
      expect(job.steps.first.state, StepState.skipped);
      expect(job.steps.first.result, {'build': 42});
      expect(job.steps.first.message, 'Already done.');
      expect(job.steps.last.state, StepState.succeeded);
    });

    test('fail when the check fails', () async {
      final scripted = ScriptedStep(
        onRun: (input, context) async => const StepFailed('first'),
        onAlreadyDone: (input, context) async => throw StateError('store down'),
      );
      harness = JobHarness.create(scripted: scripted);
      final failed = await harness.run([harness.script(sideEffect: true)]);

      await harness.runner.resume(failed.id);
      final job = await harness.runner.whenFinished(failed.id);

      expect(job.state, JobState.failed);
      expect(
        job.steps.single.message,
        'Could not tell whether the work was done already: '
        'Bad state: store down',
      );
      expect(scripted.runs, hasLength(1));
    });

    test('are never checked when they have no side effects', () async {
      final scripted = ScriptedStep(
        onRun: (input, context) async => const StepFailed('first'),
      );
      harness = JobHarness.create(scripted: scripted);
      final failed = await harness.run([harness.script()]);

      await harness.runner.resume(failed.id);
      await harness.runner.whenFinished(failed.id);

      expect(scripted.checks, isEmpty);
      expect(scripted.runs, hasLength(2));
    });
  });

  group('step outcomes', () {
    test('a skipped step is recorded and the job goes on', () async {
      final scripted = ScriptedStep(
        onRun: (input, context) async => const StepSkipped('not needed'),
      );
      harness = JobHarness.create(scripted: scripted);

      final job = await harness.run([harness.script(), harness.command('x')]);

      expect(job.state, JobState.succeeded);
      expect(job.steps.first.state, StepState.skipped);
      expect(job.steps.first.message, 'not needed');
    });

    test('an exception is a failure with its message', () async {
      final scripted = ScriptedStep(
        onRun: (input, context) async => throw StateError('boom'),
      );
      harness = JobHarness.create(scripted: scripted);

      final job = await harness.run([harness.script()]);

      expect(job.state, JobState.failed);
      expect(job.steps.single.message, 'Bad state: boom');
    });

    test('a failure message is masked', () async {
      harness.masker.add('hunter2-secret');
      final scripted = ScriptedStep(
        onRun: (input, context) async =>
            const StepFailed('login failed with hunter2-secret'),
      );
      harness = JobHarness.create(scripted: scripted);
      harness.masker.add('hunter2-secret');

      final job = await harness.run([harness.script()]);

      expect(job.steps.single.message, 'login failed with ***');
      expect(job.message, isNot(contains('hunter2')));
    });

    test('a result that cannot be encoded fails the step', () async {
      harness = JobHarness.create(scripted: ScriptedStep(encodeFails: true));

      final job = await harness.run([harness.script()]);

      expect(job.steps.single.state, StepState.failed);
      expect(job.steps.single.message, contains('cannot be stored'));
    });

    test('a step kind the engine does not have fails', () async {
      await harness.jobs.create(
        JobRecord(
          id: 'job_x',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.queued,
          createdAt: harness.clock.now(),
        ),
        const [
          StepRecord(
            jobId: 'job_x',
            ordinal: 0,
            kind: 'mystery',
            sideEffect: false,
            input: {},
          ),
        ],
      );

      await harness.runner.start('job_x');
      final job = await harness.runner.whenFinished('job_x');

      expect(job.state, JobState.failed);
      expect(
        job.steps.single.message,
        'The engine has no step of kind "mystery".',
      );
    });

    test('an input the step cannot read fails', () async {
      final job = await harness.run([
        harness.script(input: {'invalid': true}),
      ]);

      expect(job.steps.single.message, contains('invalid input'));
    });
  });

  group('context', () {
    test('tells a step who it is and whether the job is stopping', () async {
      final inside = Completer<void>();
      final release = Completer<void>();
      final seen = <String>[];
      final scripted = ScriptedStep(
        onRun: (input, context) async {
          seen.add('${context.jobId} ${context.ordinal} ${context.isStopping}');
          inside.complete();
          await release.future;
          seen.add('stopping ${context.isStopping}');
          return const StepFailed('stopped');
        },
      );
      harness = JobHarness.create(scripted: scripted);
      final created = await harness.create([harness.script()]);
      await harness.runner.start(created.id);
      await inside.future;

      final cancelling = harness.runner.cancel(created.id);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await cancelling;

      expect(seen, ['${created.id} 0 false', 'stopping true']);
    });
  });

  group('output', () {
    test('goes to onLine as well as the log', () async {
      harness.supervisor.handler = (process) async {
        await process.emit('alpha');
        await process.emit('beta', stream: LogStream.stderr);
        return 0;
      };
      final lines = <String>[];
      final scripted = ScriptedStep(
        onRun: (input, context) async {
          await context.run(
            const ProcessCommand('tool'),
            onLine: (line) => lines.add('${line.stream.name}:${line.text}'),
          );
          return const StepSucceeded({});
        },
      );
      harness = JobHarness.create(
        scripted: scripted,
        handler: harness.supervisor.handler,
      );

      final job = await harness.run([harness.script()]);

      expect(lines, ['stdout:alpha', 'stderr:beta']);
      expect(harness.logLines(job.id), ['0:alpha', '0:beta']);
    });

    test(
      'a parser that throws fails the step, and the log is complete',
      () async {
        final scripted = ScriptedStep(
          onRun: (input, context) async {
            await context.run(
              const ProcessCommand('tool'),
              onLine: (line) => throw const FormatException('bad line'),
            );
            return const StepSucceeded({});
          },
        );
        harness = JobHarness.create(
          scripted: scripted,
          handler: (process) async {
            await process.emit('one');
            await process.emit('two');
            return 0;
          },
        );

        final job = await harness.run([harness.script()]);

        expect(job.steps.single.state, StepState.failed);
        expect(job.steps.single.message, contains('bad line'));
        expect(harness.logLines(job.id), ['0:one', '0:two']);
      },
    );
  });

  group('interruptAll', () {
    test(
      'stops a step without side effects; the job can simply resume',
      () async {
        final started = Completer<void>();
        harness.supervisor.handler = _hangs(started);
        final created = await harness.create([harness.command('long')]);
        await harness.runner.start(created.id);
        await started.future;

        await harness.runner.interruptAll();
        final job = await harness.runner.get(created.id);

        expect(job.state, JobState.interrupted);
        expect(job.steps.single.state, StepState.interrupted);
        expect(harness.supervisor.processes.single.wasCancelled, isTrue);
        expect(harness.runner.activeJobs, isEmpty);
      },
    );

    test('makes a job with an interrupted side-effect step wait', () async {
      final started = Completer<void>();
      harness.supervisor.handler = _hangs(started);
      final created = await harness.create([
        harness.command('upload', sideEffect: true),
      ]);
      await harness.runner.start(created.id);
      await started.future;

      await harness.runner.interruptAll();
      final job = await harness.runner.get(created.id);

      expect(job.state, JobState.waitingForResume);
      expect(job.steps.single.state, StepState.interrupted);
      expect(job.message, 'The engine stopped while the job was running.');
    });

    test('leaves a job succeeded whose last step finished anyway', () async {
      final inside = Completer<void>();
      final release = Completer<void>();
      final scripted = ScriptedStep(
        onRun: (input, context) async {
          inside.complete();
          await release.future;
          return const StepSucceeded({'ran': true});
        },
      );
      harness = JobHarness.create(scripted: scripted);
      final created = await harness.create([harness.script(sideEffect: true)]);
      await harness.runner.start(created.id);
      await inside.future;

      final interrupting = harness.runner.interruptAll();
      release.complete();
      await interrupting;

      expect((await harness.runner.get(created.id)).state, JobState.succeeded);
    });

    test('does nothing when no job runs', () async {
      await harness.runner.interruptAll();
    });
  });

  group('bookkeeping failures', () {
    test('fail the job and are reported', () async {
      final repository = _FailingRepository();
      harness = JobHarness.create(repository: repository);
      final created = await harness.create([harness.command('x')]);
      repository.failStepUpdates = true;

      await harness.runner.start(created.id);
      final job = await harness.runner.whenFinished(created.id);

      expect(job.state, JobState.failed);
      expect(job.message, startsWith('The engine failed to run the job'));
      expect(harness.errors, isNotEmpty);
    });

    test('are reported even when the job cannot be failed', () async {
      final repository = _FailingRepository();
      harness = JobHarness.create(repository: repository);
      final created = await harness.create([harness.command('x')]);
      repository
        ..failStepUpdates = true
        ..failJobStates.add(JobState.failed);

      await harness.runner.start(created.id);
      await harness.runner.whenFinished(created.id);

      expect(harness.errors, hasLength(2));
      expect(harness.runner.activeJobs, isEmpty);
    });

    test('while the job starts are thrown to the caller', () async {
      final repository = _FailingRepository();
      harness = JobHarness.create(repository: repository);
      final created = await harness.create([harness.command('x')]);
      repository.failJobStates.add(JobState.running);

      await expectLater(
        harness.runner.start(created.id),
        throwsA(isA<StateError>()),
      );
      expect(harness.runner.activeJobs, isEmpty);
    });

    test('in the cleanup are reported and the job is released', () async {
      harness = JobHarness.create(secretFiles: _FailingSecretFiles());
      final created = await harness.create([harness.command('x')]);

      await harness.runner.start(created.id);
      final job = await harness.runner.whenFinished(created.id);

      expect(job.state, JobState.succeeded);
      expect(harness.errors, hasLength(1));
      expect(harness.runner.activeJobs, isEmpty);
    });
  });
}

class _FailingRepository extends InMemoryJobRepository {
  bool failStepUpdates = false;
  final failJobStates = <JobState>{};

  @override
  Future<void> updateStep(StepRecord step) async {
    if (failStepUpdates) throw StateError('disk full');
    await super.updateStep(step);
  }

  @override
  Future<void> updateJob(JobRecord job) async {
    if (failJobStates.contains(job.state)) throw StateError('disk full');
    await super.updateJob(job);
  }
}

class _FailingSecretFiles extends InMemorySecretFileStore {
  @override
  Future<void> deleteAll(String jobId) async =>
      throw StateError('cannot delete');
}
