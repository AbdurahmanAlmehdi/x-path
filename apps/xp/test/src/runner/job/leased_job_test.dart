import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp/src/runner/job/leased_job.dart';
import 'package:xp/src/runner/job/pgid_journal.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/step_contexts.dart';

class _Masking implements OutputMasker {
  final secrets = <String>[];

  @override
  void add(String secret) => secrets.add(secret);

  @override
  StreamMasker newStream() => _Replacing(this);
}

class _Replacing implements StreamMasker {
  const new(this._masker);

  final _Masking _masker;

  @override
  String add(String piece) =>
      _masker.secrets.fold(piece, (text, s) => text.replaceAll(s, '***'));

  @override
  String flush() => '';
}

void main() {
  late Directory root;
  late RunnerPaths paths;
  late SecretArea area;
  late FakeProcessSupervisor supervisor;
  late _Masking masker;
  late List<RunnerFrame> sent;
  late LeaseOutbox outbox;
  late List<Map<String, dynamic>> uploads;
  late List<GitWorktree> removed;
  late PgidJournal journal;
  late Map<String, List<int>?> secretAnswers;
  late List<String> secretAsks;
  late Map<String, Step<Object?, Object?>> steps;

  const worktreePath = '/engine/worktrees/42/job_1';
  const mirrorPath = '/engine/mirrors/42.git';

  Map<String, dynamic> checkoutInput() => {
    'worktree': {
      'path': worktreePath,
      'mirror': {'githubRepoId': 42, 'path': mirrorPath},
      'sha': 'a' * 40,
    },
  };

  LeaseOfferFrame offer(
    List<(String, Map<String, dynamic>)> stepList, {
    List<String> secrets = const [],
    int attempts = 0,
    StepState state = StepState.pending,
  }) => LeaseOfferFrame(
    leaseId: 'lse_1',
    jobId: 'job_1',
    projectId: 'prj_1',
    sha: 'a' * 40,
    name: 'Job',
    repository: const LeaseRepository(cacheKey: '42', sshUrl: 'git@x:y/z.git'),
    stage: 0,
    capabilities: const [],
    expiresAt: DateTime.utc(2026, 10, 14, 12),
    steps: [
      for (final (ordinal, (kind, input)) in stepList.indexed)
        LeaseStep(
          ordinal: ordinal,
          kind: kind,
          sideEffect: input['sideEffect'] == true,
          state: state,
          attempts: attempts,
          input: input,
        ),
    ],
    secrets: secrets,
  );

  LeasedJob start(LeaseOfferFrame frame, {RegistryFactory? registry}) =>
      LeasedJob(
        offer: frame,
        outbox: outbox,
        environment: JobEnvironment(
          paths: paths,
          supervisor: supervisor,
          hostEnvironment: const {'PATH': '/usr/bin', 'HOME': '/home/me'},
          secretArea: area,
          journal: journal,
          power: NoPowerAssertion(),
          clock: ManualClock(DateTime.utc(2026, 10, 14, 12)),
          upload:
              ({
                required jobId,
                required leaseId,
                required name,
                required kind,
                required content,
                required size,
                required sha256,
              }) async {
                final bytes = <int>[];
                await content().forEach(bytes.addAll);
                uploads.add({
                  'jobId': jobId,
                  'leaseId': leaseId,
                  'name': name,
                  'kind': kind,
                  'bytes': bytes,
                  'size': size,
                  'sha256': sha256,
                });
              },
          removeWorktree: (worktree) async => removed.add(worktree),
        ),
        requestSecret: (key) async {
          secretAsks.add(key);
          return secretAnswers[key];
        },
        registry:
            registry ??
            (services) => StepRegistry([const CommandStep(), ...steps.values]),
      );

  List<T> frames<T extends RunnerFrame>() => sent.whereType<T>().toList();

  JobDoneFrame done() => frames<JobDoneFrame>().single;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('xp_leased_job_');
    addTearDown(() => root.deleteSync(recursive: true));
    paths = RunnerPaths(root.path);
    area = SecretArea(
      SecretLocations(
        active: paths.fallbackSecrets,
        all: [paths.fallbackSecrets],
      ),
    );
    await area.wipeAll();
    masker = _Masking();
    supervisor = FakeProcessSupervisor(
      (process) => 0,
      clock: ManualClock(DateTime.utc(2026, 10, 14, 12)),
      masker: masker,
    );
    sent = [];
    outbox = LeaseOutbox(
      jobId: 'job_1',
      leaseId: 'lse_1',
      send: sent.add,
      flushDelay: const Duration(milliseconds: 5),
    );
    uploads = [];
    removed = [];
    journal = PgidJournal(paths.state);
    secretAnswers = {};
    secretAsks = [];
    steps = {};
  });

  group('a job that succeeds', () {
    test('runs its steps in order and reports each one', () async {
      final ran = <String>[];
      steps = {
        'one': ScriptStep('one', (input, context) async {
          ran.add('one');
          return const StepSucceeded({'made': 1});
        }),
        'two': ScriptStep('two', (input, context) async {
          ran.add('two');
          return const StepSucceeded({});
        }),
      };

      final job = start(offer([('one', {}), ('two', {})]));
      await job.finished;

      expect(ran, ['one', 'two']);
      expect(
        [
          for (final f in frames<StepStateFrame>())
            (f.ordinal, f.state, f.attempts),
        ],
        [
          (0, StepState.running, 1),
          (0, StepState.succeeded, 1),
          (1, StepState.running, 1),
          (1, StepState.succeeded, 1),
        ],
      );
      expect(frames<StepStateFrame>()[1].result, {'made': 1});
      expect(done().state, JobState.succeeded);
      expect(done().message, isNull);
      expect(done().leaseId, 'lse_1');
    });

    test('streams the output of its processes in chunks', () async {
      supervisor.handler = (process) async {
        await process.emit('building');
        await process.emit('oops', stream: LogStream.stderr);
        return 0;
      };

      final job = start(
        offer([
          (
            'command',
            {
              'executable': 'make',
              'arguments': <String>[],
              'environment': <String, String>{},
              'passThroughEnvironment': <String>[],
              'secretEnvironment': <String, String>{},
              'secretFiles': <String, String>{},
            },
          ),
        ]),
      );
      await job.finished;

      final lines = [
        for (final chunk in frames<LogChunkFrame>())
          for (final line in chunk.lines) (line.stream, line.text),
      ];
      expect(lines, [
        (LogStream.stdout, 'building'),
        (LogStream.stderr, 'oops'),
      ]);
      expect(done().lastChunk, outbox.lastChunk);
    });

    test('gives each step the paths of this machine', () async {
      Map<String, dynamic>? seen;
      steps = {
        'look': ScriptStep('look', (input, context) async {
          seen = input;
          return const StepSucceeded({});
        }),
      };

      final job = start(
        offer([
          (
            'look',
            {...checkoutInput(), 'workingDirectory': '$worktreePath/app'},
          ),
        ]),
      );
      await job.finished;

      final local = p.join(paths.source, 'worktrees', '42', 'job_1');
      expect(seen!['workingDirectory'], '$local/app');
      expect((seen!['worktree'] as Map)['path'], local);
      expect(
        ((seen!['worktree'] as Map)['mirror'] as Map)['path'],
        p.join(paths.source, 'mirrors', '42.git'),
      );
    });

    test('starts every step again, but keeps the attempts', () async {
      final seenAttempts = <int>[];
      steps = {
        'one': ScriptStep('one', (input, context) async {
          return const StepSucceeded({});
        }),
      };

      final job = start(
        offer([('one', {})], attempts: 2, state: StepState.succeeded),
      );
      await job.finished;

      seenAttempts.addAll(frames<StepStateFrame>().map((f) => f.attempts));
      expect(seenAttempts, [3, 3]);
      expect(done().state, JobState.succeeded);
    });

    test(
      'asks a step with side effects whether its work exists first',
      () async {
        var asked = false;
        var ran = false;
        steps = {
          'push': _AskingStep(
            onAsk: () {
              asked = true;
              return const {'already': true};
            },
            onRun: () => ran = true,
          ),
        };

        final job = start(
          offer(
            [
              ('push', {'sideEffect': true}),
            ],
            attempts: 1,
            state: StepState.succeeded,
          ),
        );
        await job.finished;

        expect(asked, isTrue);
        expect(ran, isFalse);
        expect(frames<StepStateFrame>().last.state, StepState.skipped);
        expect(done().state, JobState.succeeded);
      },
    );
  });

  group('a job that fails', () {
    test('reports the step that failed and stops there', () async {
      var reached = false;
      steps = {
        'bad': ScriptStep(
          'bad',
          (input, context) async => const StepFailed('Gradle said no.'),
        ),
        'next': ScriptStep('next', (input, context) async {
          reached = true;
          return const StepSucceeded({});
        }),
      };

      final job = start(offer([('bad', {}), ('next', {})]));
      await job.finished;

      expect(reached, isFalse);
      expect(done().state, JobState.failed);
      expect(done().message, 'Step 0 (bad) failed: Gradle said no.');
      expect(frames<StepStateFrame>().last.message, 'Gradle said no.');
    });

    test('reports a job that stops at a gate as a failure', () async {
      steps = {
        'wait': ScriptStep(
          'wait',
          (input, context) async => const StepWaiting('Waiting for the owner.'),
        ),
      };

      final job = start(offer([('wait', {})]));
      await job.finished;

      expect(done().state, JobState.failed);
      expect(done().message, contains('stopped in state waiting_for_approval'));
      expect(done().message, contains('Waiting for the owner.'));
    });

    test('reports a step the runner does not have', () async {
      final job = start(offer([('nothing', {})]));
      await job.finished;

      expect(done().state, JobState.failed);
      expect(done().message, contains('no step of kind "nothing"'));
    });

    test('reports a setup that fails, without a secret in the words', () async {
      masker.add('hunter2');
      final job = start(
        offer([('one', {})]),
        registry: (services) => throw StateError('hunter2 is wrong'),
      );

      await job.finished;

      expect(done().state, JobState.failed);
      expect(done().message, startsWith('The runner could not run the job:'));
      expect(done().message, isNot(contains('hunter2')));
      expect(done().message, contains('***'));
    });
  });

  group('the secrets of the job', () {
    CommandInputStub command(
      Map<String, String> files,
      Map<String, String> env,
    ) => CommandInputStub(files, env);

    test(
      'are asked of the engine, given to the process and wiped with the job',
      () async {
        secretAnswers = {
          'ks': [0xfe, 0xed, 0x00],
          'pw': utf8.encode('s3cret'),
        };
        String? seenFile;
        List<int>? fileBytes;
        String? seenPassword;
        supervisor.handler = (process) async {
          seenFile = process.spec.environment['KEYSTORE'];
          fileBytes = File(seenFile!).readAsBytesSync();
          seenPassword = process.spec.environment['PASSWORD'];
          return 0;
        };

        final job = start(
          offer(
            [
              ('command', command({'KEYSTORE': 'ks'}, {'PASSWORD': 'pw'}).json),
            ],
            secrets: ['ks', 'pw'],
          ),
        );
        await job.finished;

        expect(secretAsks, unorderedEquals(['ks', 'pw']));
        expect(fileBytes, [0xfe, 0xed, 0x00]);
        expect(seenPassword, 's3cret');
        expect(masker.secrets.toSet(), {'s3cret'});
        expect(done().state, JobState.succeeded);
        // Nothing is left when the end is reported.
        expect(File(seenFile!).existsSync(), isFalse);
        expect(
          Directory(p.join(paths.fallbackSecrets, 'job_1')).existsSync(),
          isFalse,
        );
        expect(await area.recall('job_1', 'ks'), isNull);
      },
    );

    test('are wiped when the job fails', () async {
      secretAnswers = {'pw': utf8.encode('s3cret')};
      supervisor.handler = (process) => 3;

      final job = start(
        offer(
          [
            ('command', command({}, {'PASSWORD': 'pw'}).json),
          ],
          secrets: ['pw'],
        ),
      );
      await job.finished;

      expect(done().state, JobState.failed);
      expect(await area.recall('job_1', 'pw'), isNull);
      expect(
        Directory(p.join(paths.fallbackSecrets, 'job_1')).existsSync(),
        isFalse,
      );
    });

    test('fail the step when the engine refuses them', () async {
      final job = start(
        offer(
          [
            ('command', command({}, {'PASSWORD': 'pw'}).json),
          ],
          secrets: ['pw'],
        ),
      );
      await job.finished;

      expect(done().state, JobState.failed);
      expect(done().message, contains('There is no secret "pw"'));
    });
  });

  group('what the job leaves', () {
    test('is uploaded with the lease, and removed afterwards', () async {
      steps = {
        'build': ScriptStep('build', (input, context) async {
          final services = _services;
          final recorder = ArtifactRecorder(
            store: services!.artifactStore,
            repository: services.artifacts,
            clock: ManualClock(DateTime.utc(2026)),
          );
          await recorder.record(
            jobId: context.jobId,
            kind: ArtifactKind.apk,
            name: 'dev.apk',
            content: Stream.value([1, 2, 3]),
          );
          return const StepSucceeded({});
        }),
      };

      final job = start(
        offer([('build', checkoutInput())]),
        registry: (services) {
          _services = services;
          return StepRegistry([steps['build']!]);
        },
      );
      await job.finished;

      expect(uploads.single['jobId'], 'job_1');
      expect(uploads.single['leaseId'], 'lse_1');
      expect(uploads.single['name'], 'dev.apk');
      expect(uploads.single['bytes'], [1, 2, 3]);
      expect(Directory(paths.jobDirectory('job_1')).existsSync(), isFalse);
      expect(
        removed.single.path,
        p.join(paths.source, 'worktrees', '42', 'job_1'),
      );
    });

    test('fails the step when the upload fails', () async {
      steps = {
        'build': ScriptStep('build', (input, context) async {
          final recorder = ArtifactRecorder(
            store: _services!.artifactStore,
            repository: _services!.artifacts,
            clock: ManualClock(DateTime.utc(2026)),
          );
          await recorder.record(
            jobId: context.jobId,
            kind: ArtifactKind.apk,
            name: 'dev.apk',
            content: Stream.value([1]),
          );
          return const StepSucceeded({});
        }),
      };
      final failing = LeasedJob(
        offer: offer([('build', {})]),
        outbox: outbox,
        environment: JobEnvironment(
          paths: paths,
          supervisor: supervisor,
          hostEnvironment: const {},
          secretArea: area,
          journal: journal,
          power: NoPowerAssertion(),
          clock: ManualClock(DateTime.utc(2026)),
          upload: ({
            required jobId,
            required leaseId,
            required name,
            required kind,
            required content,
            required size,
            required sha256,
          }) async => throw StateError('The lease is lost.'),
          removeWorktree: (worktree) async {},
        ),
        requestSecret: (key) async => null,
        registry: (services) {
          _services = services;
          return StepRegistry([steps['build']!]);
        },
      );
      await failing.finished;

      expect(done().state, JobState.failed);
      expect(done().message, contains('The lease is lost.'));
    });

    test('is removed even if git cannot remove the worktree', () async {
      final worktree = Directory(
        p.join(paths.source, 'worktrees', '42', 'job_1'),
      )..createSync(recursive: true);
      File(p.join(worktree.path, 'x')).writeAsStringSync('x');
      steps = {
        'look': ScriptStep('look', (input, context) async {
          return const StepSucceeded({});
        }),
      };
      final job = LeasedJob(
        offer: offer([('look', checkoutInput())]),
        outbox: outbox,
        environment: JobEnvironment(
          paths: paths,
          supervisor: supervisor,
          hostEnvironment: const {},
          secretArea: area,
          journal: journal,
          power: NoPowerAssertion(),
          clock: ManualClock(DateTime.utc(2026)),
          upload: ({
            required jobId,
            required leaseId,
            required name,
            required kind,
            required content,
            required size,
            required sha256,
          }) async {},
          removeWorktree: (worktree) async => throw StateError('git broke'),
        ),
        requestSecret: (key) async => null,
        registry: (services) => StepRegistry(steps.values),
      );

      await job.finished;

      expect(worktree.existsSync(), isFalse);
      expect(done().state, JobState.succeeded);
    });
  });

  group('cancel', () {
    test(
      'stops the process group, wipes the secrets and reports nothing',
      () async {
        secretAnswers = {'pw': utf8.encode('s3cret')};
        final started = Completer<void>();
        supervisor.handler = (process) async {
          started.complete();
          await process.cancelRequested;
          return -15;
        };
        final job = start(
          offer(
            [
              ('command', const CommandInputStub({}, {'PASSWORD': 'pw'}).json),
            ],
            secrets: ['pw'],
          ),
        );
        await started.future;
        expect(await area.recall('job_1', 'pw'), isNotNull);

        await job.cancel();

        expect(supervisor.processes.single.wasCancelled, isTrue);
        expect(frames<JobDoneFrame>(), isEmpty);
        expect(await area.recall('job_1', 'pw'), isNull);
        expect(
          Directory(p.join(paths.fallbackSecrets, 'job_1')).existsSync(),
          isFalse,
        );
      },
    );

    test('stops a job that has not started its steps', () async {
      final gate = Completer<void>();
      final job = start(
        offer([('one', {})]),
        registry: (services) {
          // The job is built after this returns; hold it back a moment.
          return StepRegistry([
            ScriptStep('one', (input, context) async {
              await gate.future;
              return const StepSucceeded({});
            }),
          ]);
        },
      );

      final cancelling = job.cancel();
      gate.complete();
      await cancelling;

      expect(frames<JobDoneFrame>(), isEmpty);
    });

    test('is harmless for a job that ended', () async {
      steps = {
        'one': ScriptStep(
          'one',
          (input, context) async => const StepSucceeded({}),
        ),
      };
      final job = start(offer([('one', {})]));
      await job.finished;

      await job.cancel();

      expect(done().state, JobState.succeeded);
      expect(outbox.awaitsAcknowledgement, isFalse, reason: 'abandoned');
    });
  });

  test('keeps the process group of a running step in the journal', () async {
    final seen = Completer<String>();
    supervisor.handler = (process) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      seen.complete(File(p.join(paths.state, 'pgids.json')).readAsStringSync());
      return 0;
    };

    final job = start(
      offer([('command', const CommandInputStub({}, {}).json)]),
    );
    await job.finished;

    expect(jsonDecode(await seen.future), {'job_1/0': 4000});
    expect(File(p.join(paths.state, 'pgids.json')).existsSync(), isFalse);
  });
}

LeaseServices? _services;

/// The input of a `command` step that names secrets.
class CommandInputStub {
  const new(this.files, this.environment);

  final Map<String, String> files;
  final Map<String, String> environment;

  Map<String, dynamic> get json => {
    'executable': 'tool',
    'arguments': <String>[],
    'environment': <String, String>{},
    'passThroughEnvironment': <String>[],
    'secretEnvironment': environment,
    'secretFiles': files,
  };
}

/// A step with side effects whose work may exist already.
class _AskingStep extends Step<Map<String, dynamic>, Map<String, dynamic>> {
  const new({required this.onAsk, required this.onRun});

  final Map<String, dynamic>? Function() onAsk;
  final void Function() onRun;

  @override
  String get kind => 'push';

  @override
  bool sideEffectOf(Map<String, dynamic> input) => true;

  @override
  Map<String, dynamic> decodeInput(Map<String, dynamic> json) => json;

  @override
  Map<String, dynamic> encodeInput(Map<String, dynamic> input) => input;

  @override
  Map<String, dynamic> encodeResult(Map<String, dynamic> result) => result;

  @override
  Future<Map<String, dynamic>?> alreadyDone(
    Map<String, dynamic> input,
    StepContext context,
  ) async => onAsk();

  @override
  Future<StepOutcome<Map<String, dynamic>>> run(
    Map<String, dynamic> input,
    StepContext context,
  ) async {
    onRun();
    return const StepSucceeded({});
  }
}
