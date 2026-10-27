import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/job_harness.dart';

typedef _Outcome = StepOutcome<Map<String, dynamic>>;

/// One job to make: its stage, name and capabilities.
class _Spec {
  const new(
    this.name, {
    this.stage = 0,
    this.needs = const [],
    this.kinds = const [],
    this.narrowing = const [],
  });

  final String name;
  final int stage;
  final List<String> needs;

  /// Why the planner ruled out Linux for it.
  final List<String> narrowing;

  /// Kinds of steps the job has besides its scripted one.
  final List<String> kinds;
}

/// A scheduler over fake runners and jobs that wait until the test finishes
/// them.
class _Fixture {
  /// Steps wait until the test finishes them, unless [script] says otherwise.
  new({ScriptedStep? script}) {
    harness = JobHarness.create(
      scripted:
          script ??
          ScriptedStep(
            onRun: (input, context) {
              started.add(context.jobId);
              // A step that runs again waits for its own end.
              final earlier = _released[context.jobId];
              if (earlier == null || earlier.isCompleted) {
                _released[context.jobId] = Completer<_Outcome>();
              }
              return _released[context.jobId]!.future;
            },
          ),
    );
  }

  late final JobHarness harness;
  final runs = InMemoryRunRepository();
  final started = <String>[];
  final _released = <String, Completer<_Outcome>>{};
  final errors = <Object>[];
  late Scheduler scheduler;
  var _runs = 0;

  void build(List<SchedulerRunner> runners) => scheduler = Scheduler(
    runner: harness.runner,
    records: harness.jobs,
    runs: runs,
    events: harness.events,
    runners: runners,
    onError: (error, _) => errors.add(error),
  );

  LocalRunner local({
    Set<Capability> capabilities = const {
      Capability.flutter,
      Capability.android,
    },
    int slots = 2,
  }) => LocalRunner(
    jobs: harness.runner,
    capabilities: capabilities,
    slots: slots,
  );

  /// Makes a run of [specs] and returns the ids of its jobs by name.
  Future<Map<String, String>> run(
    List<_Spec> specs, {
    String project = 'prj_1',
    bool lock = false,
    String? id,
  }) async {
    final runId = id ?? 'run_${++_runs}';
    harness.clock.advance(const Duration(seconds: 1));
    await runs.create(
      RunRecord(
        id: runId,
        projectId: project,
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'a' * 40,
        locksProject: lock,
        createdAt: harness.clock.now(),
      ),
    );
    final ids = <String, String>{};
    for (final spec in specs) {
      final job = await harness.runner.create(
        workflowVersionId: 'wfv_1',
        projectId: project,
        runId: runId,
        stage: spec.stage,
        name: spec.name,
        capabilities: spec.needs,
        narrowing: spec.narrowing,
        steps: [
          harness.script(),
          for (final kind in spec.kinds)
            StepPlan(kind: kind, input: const {}, sideEffect: false),
        ],
      );
      ids[spec.name] = job.id;
    }
    return ids;
  }

  /// Lets the step of the job [id] end with [outcome] and waits for the job.
  Future<Job> finish(
    String id, [
    _Outcome outcome = const StepSucceeded({'ran': true}),
  ]) async {
    // The step of a job that was just resumed may not have started yet.
    while (_released[id]?.isCompleted ?? true) {
      await settle();
    }
    _released[id]!.complete(outcome);
    final job = await harness.runner.whenFinished(id);
    await scheduler.pump();
    return job;
  }

  Future<JobState> state(String id) async =>
      (await harness.runner.get(id)).state;

  Future<String?> message(String id) async =>
      (await harness.runner.get(id)).message;

  /// Lets the engine's tasks run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));
}

void main() {
  late _Fixture f;

  setUp(() => f = _Fixture());

  group('stages', () {
    test('start when the stage before succeeded, not before', () async {
      f.build([f.local()]);
      final ids = await f.run([
        const _Spec('prepare'),
        const _Spec('build a', stage: 1),
        const _Spec('build b', stage: 1),
        const _Spec('tag', stage: 2),
      ]);

      await f.scheduler.pump();
      expect(await f.state(ids['prepare']!), JobState.running);
      expect(await f.state(ids['build a']!), JobState.queued);
      expect(
        await f.message(ids['build a']!),
        isNull,
        reason: 'a job that waits for its stage has nothing to say yet',
      );

      await f.finish(ids['prepare']!);
      await f.settle();
      expect(await f.state(ids['build a']!), JobState.running);
      expect(await f.state(ids['build b']!), JobState.running);
      expect(await f.state(ids['tag']!), JobState.queued);

      await f.finish(ids['build a']!);
      await f.settle();
      expect(await f.state(ids['tag']!), JobState.queued);

      await f.finish(ids['build b']!);
      await f.settle();
      expect(await f.state(ids['tag']!), JobState.running);
      await f.finish(ids['tag']!);
      final run = await RunService(
        runs: f.runs,
        jobs: f.harness.jobs,
        control: f.scheduler,
      ).get('run_1');
      expect(run.state, RunState.succeeded);
      expect(f.errors, isEmpty);
    });

    test(
      'are held back by a failed job, with the reason, until it is resumed',
      () async {
        f.build([f.local()]);
        final ids = await f.run([
          const _Spec('prepare'),
          const _Spec('build', stage: 1),
        ]);
        await f.scheduler.pump();

        await f.finish(ids['prepare']!, const StepFailed('boom'));
        await f.settle();

        expect(await f.state(ids['build']!), JobState.queued);
        expect(
          await f.message(ids['build']!),
          'Waiting for job prepare (failed) of stage 0 to succeed.',
        );
        final resumed = await f.scheduler.resume(ids['prepare']!);
        expect(resumed.state, JobState.running);
        await f.finish(ids['prepare']!);
        await f.settle();
        expect(await f.state(ids['build']!), JobState.running);
      },
    );

    test('do not start the queued siblings of a failed job', () async {
      f.build([f.local(slots: 1)]);
      final ids = await f.run([const _Spec('a'), const _Spec('b')]);
      await f.scheduler.pump();
      expect(await f.state(ids['a']!), JobState.running);
      expect(await f.state(ids['b']!), JobState.queued);

      await f.finish(ids['a']!, const StepFailed('boom'));
      await f.settle();

      expect(await f.state(ids['b']!), JobState.queued);
      expect(
        await f.message(ids['b']!),
        'Waiting for job a (failed) of stage 0 to succeed.',
      );
    });

    test('are held back by a cancelled job too', () async {
      f.build([f.local()]);
      final ids = await f.run([
        const _Spec('prepare'),
        const _Spec('build', stage: 1),
      ]);
      await f.scheduler.pump();

      await f.scheduler.cancel(ids['prepare']!);
      await f.settle();

      expect(await f.state(ids['prepare']!), JobState.cancelled);
      expect(await f.state(ids['build']!), JobState.queued);
      expect(
        await f.message(ids['build']!),
        contains('(cancelled) of stage 0'),
      );
    });
  });

  group('slots', () {
    test('limit how many jobs run at once, in the order of the runs', () async {
      f.build([f.local(slots: 1)]);
      final first = await f.run([const _Spec('one')]);
      final second = await f.run([const _Spec('two')]);
      final third = await f.run([const _Spec('three')]);

      await f.scheduler.pump();

      expect(await f.state(first['one']!), JobState.running);
      expect(await f.state(second['two']!), JobState.queued);
      expect(
        await f.message(second['two']!),
        'Waiting for a free slot on local.',
      );
      await f.finish(first['one']!);
      await f.settle();
      expect(await f.state(second['two']!), JobState.running);
      expect(await f.state(third['three']!), JobState.queued);
      await f.finish(second['two']!);
      await f.settle();
      expect(await f.state(third['three']!), JobState.running);
    });

    test(
      'are counted from the jobs that run, even ones nobody scheduled',
      () async {
        f.build([f.local(slots: 1)]);
        final loose = await f.harness.create([f.harness.script()]);
        await f.harness.runner.start(loose.id);
        final ids = await f.run([const _Spec('one')]);

        await f.scheduler.pump();

        expect(await f.state(ids['one']!), JobState.queued);
      },
    );

    test('are not held back by a job that cannot start', () async {
      f.build([f.local(slots: 3)]);
      final ids = await f.run([
        const _Spec('needs ios', needs: ['ios-sign']),
        const _Spec('plain'),
      ]);

      await f.scheduler.pump();

      expect(await f.state(ids['needs ios']!), JobState.queued);
      expect(await f.state(ids['plain']!), JobState.running);
    });
  });

  group('capabilities', () {
    test('send a job to a runner that can do everything it needs', () async {
      final mac = f.local(
        capabilities: {Capability.flutter, Capability.iosSign},
      );
      f.build([_Named('linux', f.local()), mac]);
      final ids = await f.run([
        const _Spec('ios', needs: ['flutter', 'ios-sign']),
      ]);

      await f.scheduler.pump();

      expect(await f.state(ids['ios']!), JobState.running);
    });

    test('say when no runner can do a job', () async {
      f.build([f.local()]);
      final ids = await f.run([
        const _Spec('ios', needs: ['flutter', 'ios-sign']),
        const _Spec('unknown', needs: ['lasers']),
      ]);

      await f.scheduler.pump();

      expect(
        await f.message(ids['ios']!),
        'No runner can do flutter, ios-sign.',
      );
      expect(await f.message(ids['unknown']!), isNull);
      expect(
        await f.state(ids['unknown']!),
        JobState.running,
        reason: 'a capability nobody knows is no requirement',
      );
    });

    test('a paired runner compares by value', () {
      PairedRunner runner({
        bool connected = false,
        List<MissingCapability> missing = const [],
      }) => PairedRunner(
        id: 'rnr_1',
        name: 'aws',
        capabilities: const {Capability.android},
        connected: connected,
        lastSeen: DateTime.utc(2026, 10, 22),
        missing: missing,
      );

      expect(runner(), runner());
      expect(runner(), isNot(runner(connected: true)));
      expect(
        runner(),
        isNot(
          runner(
            missing: const [
              MissingCapability(capability: 'ios-linux', reason: 'r', fix: ''),
            ],
          ),
        ),
      );
    });

    test(
      'name the paired runners that could do a job and are offline',
      () async {
        final paired = _PairedRunners([
          PairedRunner(
            id: 'rnr_aws',
            name: 'AWS Instance',
            capabilities: const {Capability.flutter, Capability.iosSign},
            connected: false,
            lastSeen: DateTime.utc(2026, 10, 22, 14, 2, 30),
          ),
          const PairedRunner(
            id: 'rnr_new',
            name: 'never seen',
            capabilities: {Capability.iosSign},
            connected: false,
          ),
          // Connected but not probed yet: not offline.
          const PairedRunner(
            id: 'rnr_now',
            name: 'connecting',
            capabilities: {Capability.iosSign},
            connected: true,
          ),
        ]);
        f.build([f.local()]);
        f.scheduler.pairedRunners = paired;
        final ids = await f.run([
          const _Spec('ios', needs: ['ios-sign']),
          const _Spec('mac', needs: ['ios-sign']),
          const _Spec('linux', needs: ['swift-linux']),
        ]);

        await f.scheduler.pump();

        expect(
          await f.message(ids['ios']!),
          'No connected runner can do ios-sign. AWS Instance offers ios-sign; '
          'offline since 2026-10-22 14:02 UTC. never seen offers ios-sign; '
          'offline.',
        );
        expect(await f.message(ids['mac']!), await f.message(ids['ios']!));
        expect(await f.message(ids['linux']!), 'No runner can do swift-linux.');
        expect(paired.reads, 1, reason: 'read once per pass');
      },
    );

    test('name the connected runners that lack a needed capability, with '
        'the fix', () async {
      const oldPin = MissingCapability(
        capability: 'ios-linux',
        reason:
            'omarchy-apple-dev is at 4e170a0ce5f2; this XPath needs '
            '2d03f766859e',
        fix:
            'git -C /srv/oad fetch https://github.com/o/oad 2d03f76 && '
            'git -C /srv/oad checkout 2d03f76',
      );
      f.build([f.local()]);
      f.scheduler.pairedRunners = _PairedRunners([
        const PairedRunner(
          id: 'rnr_linux',
          name: 'hetzner',
          capabilities: {Capability.flutter, Capability.swiftLinux},
          connected: true,
          missing: [
            oldPin,
            MissingCapability(
              capability: 'android',
              reason: 'no JDK: java not found',
              fix: 'install JDK 17',
            ),
          ],
        ),
        const PairedRunner(
          id: 'rnr_bare',
          name: 'bare',
          capabilities: {},
          connected: true,
          missing: [
            MissingCapability(
              capability: 'ios-sign',
              reason: 'not macOS',
              fix: '',
            ),
          ],
        ),
      ]);
      final ids = await f.run([
        const _Spec('ios', needs: ['flutter', 'ios-sign|ios-linux']),
      ]);

      await f.scheduler.pump();

      const why =
          'No connected runner can do flutter, ios-sign or ios-linux. '
          'hetzner lacks ios-linux: omarchy-apple-dev is at 4e170a0ce5f2; '
          'this XPath needs 2d03f766859e. To fix it: git -C /srv/oad fetch '
          'https://github.com/o/oad 2d03f76 && git -C /srv/oad checkout '
          '2d03f76. bare lacks ios-sign: not macOS.';
      expect(await f.message(ids['ios']!), why);
      expect(
        (await f.scheduler.placement(
          ['flutter', 'ios-sign|ios-linux'],
          ['build.ios'],
        )).waitReason,
        why,
        reason: 'the dry run says the same',
      );
    });

    test('say it once, not on every pass', () async {
      f.build([f.local()]);
      final ids = await f.run([
        const _Spec('ios', needs: ['ios-sign']),
      ]);
      await f.scheduler.pump();
      final before = f.harness.events.head;

      await f.scheduler.pump();
      await f.scheduler.pump();

      expect(f.harness.events.head, before);
      expect(await f.message(ids['ios']!), 'No runner can do ios-sign.');
    });

    test('run a job that needs nothing anywhere', () async {
      f.build([f.local(capabilities: const {})]);
      final ids = await f.run([const _Spec('git only')]);

      await f.scheduler.pump();

      expect(await f.state(ids['git only']!), JobState.running);
    });
  });

  group('ios-sign', () {
    test('runs one job at a time on a machine, beside other jobs', () async {
      f.build([
        f.local(
          capabilities: {Capability.flutter, Capability.iosSign},
          slots: 4,
        ),
      ]);
      final ids = await f.run([
        const _Spec('ios 1', needs: ['ios-sign']),
        const _Spec('ios 2', needs: ['ios-sign']),
        const _Spec('flutter', needs: ['flutter']),
      ]);

      await f.scheduler.pump();

      expect(await f.state(ids['ios 1']!), JobState.running);
      expect(await f.state(ids['ios 2']!), JobState.queued);
      expect(
        await f.message(ids['ios 2']!),
        'Waiting for the ios-sign job that runs now: one at a time.',
      );
      expect(await f.state(ids['flutter']!), JobState.running);
      await f.finish(ids['ios 1']!);
      await f.settle();
      expect(await f.state(ids['ios 2']!), JobState.running);
    });

    test('counts a signing job that runs from before the pass', () async {
      Scheduler first() => f.scheduler;
      final mac = {Capability.flutter, Capability.iosSign};
      f.build([f.local(capabilities: mac, slots: 4)]);
      final earlier = await f.run([
        const _Spec('ios 1', needs: ['ios-sign']),
      ]);
      await first().pump();
      expect(await f.state(earlier['ios 1']!), JobState.running);

      // The engine restarted: a new scheduler learns it from the database.
      f.build([f.local(capabilities: mac, slots: 4)]);
      final later = await f.run([
        const _Spec('ios 2', needs: ['ios-sign']),
      ]);
      await f.scheduler.pump();

      expect(await f.state(later['ios 2']!), JobState.queued);
      expect(
        await f.message(later['ios 2']!),
        'Waiting for the ios-sign job that runs now: one at a time.',
      );
    });

    test('is one job per machine, so another Mac takes the next', () async {
      f.build([
        f.local(capabilities: {Capability.iosSign}),
        _Named('mini', f.local(capabilities: {Capability.iosSign})),
      ]);
      final ids = await f.run([
        const _Spec('ios 1', needs: ['ios-sign']),
        const _Spec('ios 2', needs: ['ios-sign']),
        const _Spec('ios 3', needs: ['ios-sign']),
      ]);

      await f.scheduler.pump();

      expect(await f.state(ids['ios 1']!), JobState.running);
      expect(await f.state(ids['ios 2']!), JobState.running);
      expect(await f.state(ids['ios 3']!), JobState.queued);
    });
  });

  group('placement (a dry run, UX-01)', () {
    PairedRunner paired(String id, String name, {bool connected = true}) =>
        PairedRunner(
          id: id,
          name: name,
          capabilities: const {Capability.iosSign},
          connected: connected,
        );

    test('says the engine can run a job it has what for', () async {
      f.build([f.local()]);

      expect(await f.scheduler.placement(['flutter'], ['build.android']), (
        local: true,
        runner: null,
        waitReason: null,
      ));
    });

    test('names the connected runner a job can go to', () async {
      f
        ..build([f.local(), _Named('linux', f.local())])
        ..scheduler.pairedRunners = _PairedRunners([
          paired('linux', 'linux-builder-01'),
        ]);

      expect(await f.scheduler.placement(['android'], ['build.android']), (
        local: true,
        runner: 'linux-builder-01',
        waitReason: null,
      ));
      f.build([_Named('linux', f.local())]);
      expect(
        (await f.scheduler.placement(['android'], ['build.android'])).runner,
        'linux',
      );
    });

    test('says why a job no runner can take would wait', () async {
      f.build([]);
      expect(
        (await f.scheduler.placement([], ['command'])).waitReason,
        'No runner is connected.',
      );
      f.build([f.local()]);
      expect(
        (await f.scheduler.placement(['ios-sign'], ['build.ios'])).waitReason,
        'No runner can do ios-sign.',
      );

      f.scheduler.pairedRunners = _PairedRunners([
        paired('rnr_mini', 'mini', connected: false),
      ]);
      expect(await f.scheduler.placement(['ios-sign'], ['build.ios']), (
        local: false,
        runner: null,
        waitReason:
            'No connected runner can do ios-sign. mini offers ios-sign; '
            'offline.',
      ));

      f.build([
        f.local(capabilities: {Capability.flutter}),
        _EngineOnlyRefused(f.local(capabilities: {Capability.iosSign})),
      ]);
      expect(
        (await f.scheduler.placement(
          ['ios-sign'],
          ['upload.appStore'],
        )).waitReason,
        'Only the engine runs upload.appStore, and the engine cannot do '
        'ios-sign.',
      );
    });
  });

  group('any-of needs (ADR 0014)', () {
    const both = 'ios-sign|ios-linux';

    _Spy spy(String id, Capability ios, {int slots = 2}) =>
        _Spy(id, f.local(slots: slots), f.harness.jobs)..extra.add(ios);

    test('place an iOS build on a Mac or on a Linux runner', () async {
      for (final ios in [Capability.iosSign, Capability.iosLinux]) {
        final runner = spy('rnr_${ios.wire}', ios);
        f.build([f.local(), runner]);
        final ids = await f.run([
          const _Spec('ios', needs: ['flutter', both]),
        ]);

        await f.scheduler.pump();

        expect(runner.launched, [ids['ios']], reason: ios.wire);
      }
    });

    test('prefer a Mac when both are free, whatever the order', () async {
      final linux = spy('rnr_linux', Capability.iosLinux);
      final mac = spy('rnr_mac', Capability.iosSign);
      f.build([linux, mac]);
      final ids = await f.run([
        const _Spec('ios', needs: [both]),
      ]);

      await f.scheduler.pump();

      expect(mac.launched, [ids['ios']]);
      expect(linux.launched, isEmpty);
    });

    test('take the Linux runner while the Mac runs an iOS job', () async {
      final linux = spy('rnr_linux', Capability.iosLinux);
      final mac = spy('rnr_mac', Capability.iosSign);
      f.build([linux, mac]);
      final ids = await f.run([
        const _Spec('signing', needs: ['ios-sign']),
        const _Spec('either', needs: [both]),
      ]);

      await f.scheduler.pump();

      expect(mac.launched, [ids['signing']]);
      expect(linux.launched, [ids['either']]);
    });

    test('keep one iOS job per machine on Linux too', () async {
      final linux = spy('rnr_linux', Capability.iosLinux, slots: 4);
      f.build([linux]);
      final ids = await f.run([
        const _Spec('ios 1', needs: [both]),
        const _Spec('ios 2', needs: [both]),
        const _Spec('plain'),
      ]);

      await f.scheduler.pump();

      expect(linux.launched, [ids['ios 1'], ids['plain']]);
      expect(
        await f.message(ids['ios 2']!),
        'Waiting for the iOS job that runs now: one at a time.',
      );
    });

    test('say which capabilities would do when no runner has one', () async {
      f.build([f.local()]);
      final ids = await f.run([
        const _Spec('ios', needs: ['flutter', both]),
      ]);

      await f.scheduler.pump();

      expect(
        await f.message(ids['ios']!),
        'No runner can do flutter, ios-sign or ios-linux.',
      );
    });

    test('say why Linux was ruled out while a narrowed job waits', () async {
      const flavor =
          'the job uses Shorebird iOS, which needs macOS (Shorebird iOS on '
          'Linux is not decided)';
      final linux = spy('rnr_linux', Capability.iosLinux);
      f.build([f.local(), linux]);
      final ids = await f.run([
        const _Spec('ios', needs: ['flutter', 'ios-sign'], narrowing: [flavor]),
      ]);

      await f.scheduler.pump();

      expect(linux.launched, isEmpty);
      expect(
        await f.message(ids['ios']!),
        'No runner can do flutter, ios-sign. It needs ios-sign: the job uses '
        'Shorebird iOS, which needs macOS (Shorebird iOS on Linux is not '
        'decided).',
      );
    });

    test('say why Linux was ruled out while a busy Mac is awaited', () async {
      const flavor =
          'the job uses Shorebird iOS, which needs macOS (Shorebird iOS on '
          'Linux is not decided)';
      final mac = spy('rnr_mac', Capability.iosSign);
      final linux = spy('rnr_linux', Capability.iosLinux);
      f.build([mac, linux]);
      final ids = await f.run([
        const _Spec('signing', needs: ['ios-sign']),
        const _Spec('narrowed', needs: ['ios-sign'], narrowing: [flavor]),
      ]);

      await f.scheduler.pump();

      expect(mac.launched, [ids['signing']]);
      expect(linux.launched, isEmpty);
      final message = await f.message(ids['narrowed']!);
      expect(message, startsWith('Waiting for the ios-sign job that runs now'));
      expect(message, endsWith('It needs ios-sign: $flavor.'));
    });

    test('know whether any runner could ever take a job', () async {
      final mac = [
        const CapabilityNeed([Capability.iosSign]),
      ];
      f.build([f.local()]);
      expect(await f.scheduler.couldRun(mac), isFalse);

      f.scheduler.pairedRunners = _PairedRunners([
        const PairedRunner(
          id: 'rnr_away',
          name: 'away',
          capabilities: {Capability.iosSign},
          connected: false,
        ),
      ]);
      expect(await f.scheduler.couldRun(mac), isTrue);

      f.build([spy('rnr_mac', Capability.iosSign)]);
      expect(await f.scheduler.couldRun(mac), isTrue);
      expect(
        await f.scheduler.couldRun([
          const CapabilityNeed([Capability.swiftLinux]),
        ]),
        isFalse,
      );
    });
  });

  group('the project lock', () {
    test(
      'keeps a second production release queued until the first ended',
      () async {
        f.build([f.local(slots: 4)]);
        final first = await f.run([const _Spec('prepare')], lock: true);
        final second = await f.run([const _Spec('prepare')], lock: true);

        await f.scheduler.pump();

        expect(await f.state(first['prepare']!), JobState.running);
        expect(await f.state(second['prepare']!), JobState.queued);
        expect(
          await f.message(second['prepare']!),
          'Waiting for run run_1 to finish: only one production release or '
          'patch of a project runs at a time.',
        );
        await f.finish(first['prepare']!);
        await f.settle();
        expect(await f.state(second['prepare']!), JobState.running);
      },
    );

    test('is held between the stages of a release', () async {
      f.build([f.local(slots: 4)]);
      final first = await f.run([
        const _Spec('prepare'),
        const _Spec('build', stage: 1),
      ], lock: true);
      final second = await f.run([const _Spec('prepare')], lock: true);
      await f.scheduler.pump();

      await f.finish(first['prepare']!);
      await f.settle();

      expect(await f.state(first['build']!), JobState.running);
      expect(await f.state(second['prepare']!), JobState.queued);
    });

    test('is held while a gate waits for the owner', () async {
      final gate = ScriptedStep(
        kind: 'gate',
        onRun: (input, context) =>
            Future<_Outcome>.value(const StepWaiting('Waiting for the owner.')),
      );
      f = _Fixture(script: gate);
      f.build([f.local(slots: 4)]);
      final first = await f.run([const _Spec('prepare')], lock: true);
      final second = await f.run([const _Spec('prepare')], lock: true);

      await f.scheduler.pump();
      await f.settle();

      expect(await f.state(first['prepare']!), JobState.waitingForApproval);
      expect(await f.state(second['prepare']!), JobState.queued);
    });

    test(
      'is let go when the release fails, and asked for again by a resume',
      () async {
        f.build([f.local(slots: 4)]);
        final first = await f.run([
          const _Spec('prepare'),
          const _Spec('build', stage: 1),
        ], lock: true);
        final second = await f.run([const _Spec('prepare')], lock: true);
        await f.scheduler.pump();
        await f.finish(first['prepare']!);
        await f.settle();

        await f.finish(first['build']!, const StepFailed('boom'));
        await f.settle();

        expect(await f.state(second['prepare']!), JobState.running);
        final resumed = await f.scheduler.resume(first['build']!);
        expect(resumed.state, JobState.queued);
        expect(
          await f.message(first['build']!),
          'Waiting for run run_2 to finish: only one production release or '
          'patch of a project runs at a time.',
        );
        await f.finish(second['prepare']!);
        await f.settle();
        expect(await f.state(first['build']!), JobState.running);
      },
    );

    test('goes to the run that waited longest', () async {
      f.build([
        f.local(capabilities: {Capability.flutter}),
      ]);
      final first = await f.run([const _Spec('prepare')], lock: true);
      final slow = await f.run([
        const _Spec('prepare', needs: ['android']),
      ], lock: true);
      final later = await f.run([const _Spec('prepare')], lock: true);
      await f.scheduler.pump();
      await f.finish(first['prepare']!);
      await f.settle();

      // The older run cannot start: no runner has android. The newer one does
      // not jump the queue.
      expect(await f.state(slow['prepare']!), JobState.queued);
      expect(await f.state(later['prepare']!), JobState.queued);
      expect(
        await f.message(later['prepare']!),
        startsWith('Waiting for run run_2 to finish'),
      );
    });

    test("is the project's alone; others are not held up", () async {
      f.build([f.local(slots: 4)]);
      final first = await f.run([const _Spec('prepare')], lock: true);
      final other = await f.run(
        [const _Spec('prepare')],
        lock: true,
        project: 'prj_2',
      );
      final dev = await f.run([const _Spec('build')]);

      await f.scheduler.pump();

      expect(await f.state(first['prepare']!), JobState.running);
      expect(await f.state(other['prepare']!), JobState.running);
      expect(await f.state(dev['build']!), JobState.running);
    });

    test('is let go at the end of a release, so the next one starts', () async {
      f.build([f.local(slots: 4)]);
      final first = await f.run([const _Spec('prepare')], lock: true);
      final second = await f.run([const _Spec('prepare')], lock: true);
      await f.scheduler.pump();
      await f.finish(first['prepare']!);
      await f.settle();

      expect((await f.runs.get('run_1'))!.lockHeld, isFalse);
      expect((await f.runs.get('run_2'))!.lockHeld, isTrue);
      await f.finish(second['prepare']!);
      await f.settle();
      expect((await f.runs.get('run_2'))!.lockHeld, isFalse);
    });
  });

  group('resume and cancel', () {
    test('resume starts a job that is not part of a run at once', () async {
      f.build([f.local()]);
      f.harness.supervisor.handler = (process) => 1;
      final failed = await f.harness.run([f.harness.command('x')]);
      f.harness.supervisor.handler = (process) => 0;

      final resumed = await f.scheduler.resume(failed.id);

      expect(resumed.state, JobState.running);
    });

    test('resume says when there is no such job', () async {
      f.build([f.local()]);

      await expectLater(
        f.scheduler.resume('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });

    test('resume refuses a job that cannot be resumed', () async {
      f.build([f.local()]);
      final ids = await f.run([const _Spec('a')]);

      await expectLater(
        f.scheduler.resume(ids['a']!),
        throwsA(isA<JobStateException>()),
      );
    });

    test('get shows the job', () async {
      f.build([f.local()]);
      final ids = await f.run([const _Spec('a')]);

      expect((await f.scheduler.get(ids['a']!)).name, 'a');
    });

    test(
      'cancel stops a running job and lets the next take its place',
      () async {
        f.build([f.local(slots: 1)]);
        f.harness.supervisor.handler = (process) async {
          await Completer<void>().future;
          return 0;
        };
        final ids = <String>[];
        for (final name in ['one', 'two']) {
          f.harness.clock.advance(const Duration(seconds: 1));
          await f.runs.create(
            RunRecord(
              id: 'run_$name',
              projectId: 'prj_1',
              workflowId: 'wf_1',
              workflowVersionId: 'wfv_1',
              sha: 'a' * 40,
              locksProject: false,
              createdAt: f.harness.clock.now(),
            ),
          );
          final job = await f.harness.runner.create(
            workflowVersionId: 'wfv_1',
            projectId: 'prj_1',
            runId: 'run_$name',
            name: name,
            steps: [f.harness.command(name)],
          );
          ids.add(job.id);
        }
        await f.scheduler.pump();
        expect(await f.state(ids.first), JobState.running);

        final cancelled = await f.scheduler.cancel(ids.first);
        await f.settle();

        expect(cancelled.state, JobState.cancelled);
        expect(await f.state(ids.last), JobState.running);
        await f.scheduler.cancel(ids.last);
      },
    );
  });

  group('waiting for approval', () {
    test('resumeWaiting puts the jobs of a project back in line', () async {
      var open = false;
      final gate = ScriptedStep(
        kind: 'gate',
        onRun: (input, context) => Future<_Outcome>.value(
          open
              ? const StepSucceeded({'ran': true})
              : const StepWaiting('Waiting.'),
        ),
      );
      f = _Fixture(script: gate);
      f.build([f.local()]);
      final mine = await f.run([const _Spec('prepare')], lock: true);
      final other = await f.run(
        [const _Spec('prepare')],
        lock: true,
        project: 'prj_2',
      );
      await f.scheduler.pump();
      await f.settle();
      expect(await f.state(mine['prepare']!), JobState.waitingForApproval);
      expect(await f.state(other['prepare']!), JobState.waitingForApproval);
      final loose = await f.harness.create([f.harness.script()]);

      // Still undecided: they wait again.
      await f.scheduler.resumeWaiting(projectId: 'prj_1');
      await f.settle();
      expect(await f.state(mine['prepare']!), JobState.waitingForApproval);

      open = true;
      await f.scheduler.resumeWaiting(projectId: 'prj_1');
      await f.settle();

      expect(await f.state(mine['prepare']!), JobState.succeeded);
      expect(await f.state(other['prepare']!), JobState.waitingForApproval);
      expect(await f.state(loose.id), JobState.queued);
      await f.scheduler.resumeWaiting();
      await f.settle();
      expect(await f.state(other['prepare']!), JobState.succeeded);
    });

    test('resumeWaiting skips a job that is gone or ended meanwhile', () async {
      f.build([f.local()]);
      final stale = [
        JobRecord(
          id: 'job_gone',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.waitingForApproval,
          createdAt: f.harness.clock.now(),
          runId: 'run_1',
        ),
      ];
      f.scheduler = Scheduler(
        runner: f.harness.runner,
        records: _StaleJobs(f.harness.jobs, stale),
        runs: f.runs,
        events: f.harness.events,
        runners: [f.local()],
        onError: (error, _) => f.errors.add(error),
      );

      await f.scheduler.resumeWaiting();

      expect(f.errors, isEmpty);
    });

    test(
      'resumeWaiting leaves a waiting job that is not part of a run alone',
      () async {
        final gate = ScriptedStep(
          kind: 'gate',
          onRun: (input, context) =>
              Future<_Outcome>.value(const StepWaiting('Waiting.')),
        );
        f = _Fixture(script: gate);
        f.build([f.local()]);
        final loose = await f.harness.run([f.harness.script()]);

        await f.scheduler.resumeWaiting();

        expect(await f.state(loose.id), JobState.waitingForApproval);
      },
    );
  });

  group('runners', () {
    test('can be added and removed', () async {
      f.build([]);
      final ids = await f.run([const _Spec('a')]);
      await f.scheduler.pump();
      expect(await f.state(ids['a']!), JobState.queued);
      expect(f.scheduler.runners, isEmpty);

      f.scheduler.addRunner(f.local());
      await f.scheduler.pump();
      expect(await f.state(ids['a']!), JobState.running);
      expect(f.scheduler.runners.map((r) => r.id), ['local']);
      f.scheduler.removeRunner('local');
      expect(f.scheduler.runners, isEmpty);
    });

    test('are only asked for jobs that are still queued', () async {
      f.build([_Cancelling(f)]);
      final ids = await f.run([const _Spec('a'), const _Spec('b')]);

      await f.scheduler.pump();

      expect(await f.state(ids['a']!), JobState.cancelled);
      expect(await f.state(ids['b']!), JobState.cancelled);
      expect(f.errors, isEmpty);
    });
  });

  group('placement', () {
    _Spy spy(String id, {int slots = 2, Set<String> refuses = const {}}) =>
        _Spy(id, f.local(slots: slots), f.harness.jobs, refuses: refuses);

    test('prefers the local runner whatever the order', () async {
      final remote = spy('rnr_1');
      final local = spy('local');
      f.build([remote, local]);
      final ids = await f.run([const _Spec('a')]);

      await f.scheduler.pump();

      expect(local.launched, [ids['a']]);
      expect(remote.launched, isEmpty);
    });

    test('uses a remote runner when the engine has no free slot', () async {
      final remote = spy('rnr_1');
      final local = spy('local', slots: 1);
      f.build([local, remote]);
      final ids = await f.run([const _Spec('a'), const _Spec('b')]);

      await f.scheduler.pump();

      expect(local.launched, [ids['a']]);
      expect(remote.launched, [ids['b']]);
    });

    test('uses a remote runner for what the engine cannot do', () async {
      final remote = spy('rnr_1');
      final local = spy('local');
      remote.extra.add(Capability.iosSign);
      f.build([local, remote]);
      final ids = await f.run([
        const _Spec('ios', needs: ['ios-sign']),
      ]);

      await f.scheduler.pump();

      expect(remote.launched, [ids['ios']]);
      expect(local.launched, isEmpty);
    });

    test('gives a job to the least loaded remote runner', () async {
      final first = spy('rnr_1', slots: 4);
      final second = spy('rnr_2');
      final third = spy('rnr_3');
      f.build([first, second, third]);
      final ids = await f.run([
        const _Spec('a'),
        const _Spec('b'),
        const _Spec('c'),
        const _Spec('d'),
      ]);

      await f.scheduler.pump();

      // a: all idle, the first wins; b: the idle ones; c: the other idle one;
      // d: first has 1 of 4, the others 1 of 2.
      expect(first.launched, [ids['a'], ids['d']]);
      expect(second.launched, [ids['b']]);
      expect(third.launched, [ids['c']]);
    });

    test('never gives a job to a runner that refuses its steps', () async {
      final remote = spy('rnr_1', refuses: {'upload.play'});
      final local = spy('local', slots: 1);
      f.build([remote, local]);
      final ids = await f.run([
        const _Spec('upload', kinds: ['upload.play']),
        const _Spec('plain'),
      ]);

      await f.scheduler.pump();

      expect(local.launched, [ids['upload']]);
      expect(remote.launched, [ids['plain']]);
    });

    test('says why a job with engine-only steps waits', () async {
      final remote = spy('rnr_1', refuses: {'upload.play', 'upload.firebase'});
      remote.extra.add(Capability.iosSign);
      final local = spy('local', slots: 1);
      f.build([local, remote]);
      final ids = await f.run([
        const _Spec('hold', kinds: ['upload.play']),
        const _Spec(
          'ios',
          needs: ['ios-sign'],
          kinds: ['upload.play', 'upload.firebase', 'upload.play'],
        ),
        const _Spec('waits', kinds: ['upload.play']),
      ]);

      await f.scheduler.pump();

      expect(
        await f.message(ids['ios']!),
        'Only the engine runs upload.firebase, upload.play, and the engine '
        'cannot do ios-sign.',
      );
      expect(remote.launched, isEmpty);
      expect(
        await f.message(ids['waits']!),
        'Waiting for a free slot on local.',
      );
    });
  });

  group('cancelling a job on a remote runner', () {
    test('is left to the place that holds its lease', () async {
      f.build([f.local()]);
      final remote = _Remote({'job_remote'});
      f.scheduler.remoteJobs = remote;
      final ids = await f.run([const _Spec('a')]);
      await f.scheduler.pump();

      // The job is the remote's: the scheduler does not cancel it itself.
      remote.handled.add(ids['a']!);
      final job = await f.scheduler.cancel(ids['a']!);

      expect(remote.asked, [ids['a']]);
      expect(job.state, JobState.running);
    });

    test("is the scheduler's for any other job", () async {
      f.build([f.local()]);
      final remote = _Remote({});
      f.scheduler.remoteJobs = remote;
      final ids = await f.run([const _Spec('a')]);

      final job = await f.scheduler.cancel(ids['a']!);

      expect(remote.asked, [ids['a']]);
      expect(job.state, JobState.cancelled);
      expect(f.scheduler.remoteJobs, same(remote));
    });
  });

  group('a pass', () {
    test('does nothing once the scheduler was stopped', () async {
      f.build([f.local()]);
      final ids = await f.run([const _Spec('a')]);

      f.scheduler.stop();
      await f.scheduler.pump();

      expect(await f.state(ids['a']!), JobState.queued);
    });

    test('shares a request that comes while another waits to begin', () async {
      f.build([f.local()]);
      await f.run([const _Spec('a')]);

      final first = f.scheduler.pump();
      final second = f.scheduler.pump();
      final third = f.scheduler.pump();

      expect(identical(second, third), isTrue);
      await Future.wait([first, second, third]);
    });

    test('reports a failure and carries on', () async {
      f.build([f.local()]);
      await f.run([const _Spec('a')]);
      f.scheduler = Scheduler(
        runner: f.harness.runner,
        records: f.harness.jobs,
        runs: _FailingRuns(f.runs),
        events: f.harness.events,
        runners: [f.local()],
        onError: (error, _) => f.errors.add(error),
      );

      await f.scheduler.pump();
      await f.scheduler.pump();

      expect(f.errors, hasLength(2));
    });

    test('ignores a job whose run is gone', () async {
      f.build([f.local()]);
      await f.harness.runner.create(
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        runId: 'run_missing',
        steps: [f.harness.script()],
      );

      await f.scheduler.pump();

      expect(f.errors, isEmpty);
    });

    test('works without anyone listening for errors', () async {
      f.scheduler = Scheduler(
        runner: f.harness.runner,
        records: f.harness.jobs,
        runs: _FailingRuns(f.runs),
        events: f.harness.events,
        runners: [f.local()],
      );
      await f.run([const _Spec('a')]);

      await f.scheduler.pump();
    });
  });
}

/// A runner under another id.
class _Named implements SchedulerRunner {
  const new(this.id, this._inner);

  @override
  final String id;
  final LocalRunner _inner;

  @override
  Set<Capability> get capabilities => _inner.capabilities;

  @override
  int get slots => _inner.slots;

  @override
  bool accepts(Iterable<String> stepKinds) => _inner.accepts(stepKinds);

  @override
  Future<void> launch(String jobId) => _inner.launch(jobId);

  @override
  Future<void> whenFinished(String jobId) => _inner.whenFinished(jobId);
}

/// A remote runner: it takes no step only the engine runs.
class _EngineOnlyRefused implements SchedulerRunner {
  const new(this._inner);

  final LocalRunner _inner;

  @override
  String get id => 'rnr_remote';

  @override
  Set<Capability> get capabilities => _inner.capabilities;

  @override
  int get slots => _inner.slots;

  @override
  bool accepts(Iterable<String> stepKinds) =>
      RemoteStepPolicy.canRunRemotely(stepKinds);

  @override
  Future<void> launch(String jobId) => _inner.launch(jobId);

  @override
  Future<void> whenFinished(String jobId) => _inner.whenFinished(jobId);
}

/// A runner that finds the job cancelled when it is asked to start it.
class _Cancelling implements SchedulerRunner {
  const new(this._fixture);

  final _Fixture _fixture;

  @override
  String get id => 'racy';

  @override
  Set<Capability> get capabilities => const {};

  @override
  int get slots => 2;

  @override
  bool accepts(Iterable<String> stepKinds) => true;

  @override
  Future<void> launch(String jobId) async {
    await _fixture.harness.runner.cancel(jobId);
    await _fixture.harness.runner.start(jobId);
  }

  @override
  Future<void> whenFinished(String jobId) async {}
}

/// Runs that cannot be read.
class _FailingRuns implements RunRepository {
  const new(this._inner);

  final RunRepository _inner;

  @override
  Future<void> create(RunRecord run) => _inner.create(run);

  @override
  Future<RunRecord?> get(String id) async => throw StateError('disk on fire');

  @override
  Future<void> setLockHeld(String id, {required bool held}) =>
      _inner.setLockHeld(id, held: held);

  @override
  Future<List<RunRecord>> held() => _inner.held();

  @override
  Future<List<RunRecord>> list({
    String? projectId,
    String? workflowId,
    String? before,
    int limit = 50,
  }) => _inner.list(
    projectId: projectId,
    workflowId: workflowId,
    before: before,
    limit: limit,
  );
}

/// A job repository whose list of waiting jobs is out of date.
class _StaleJobs extends InMemoryJobRepository {
  new(this._inner, this._stale);

  final JobRepository _inner;
  final List<JobRecord> _stale;

  @override
  Future<List<JobRecord>> list({required Set<JobState> states}) async =>
      states.contains(JobState.waitingForApproval)
      ? _stale
      : await _inner.list(states: states);

  @override
  Future<JobRecord?> get(String id) => _inner.get(id);

  @override
  Future<List<StepRecord>> steps(String jobId) => _inner.steps(jobId);

  @override
  Future<List<JobRecord>> forRun(String runId) => _inner.forRun(runId);

  @override
  Future<void> updateJob(JobRecord job) => _inner.updateJob(job);

  @override
  Future<void> updateStep(StepRecord step) => _inner.updateStep(step);
}

/// A runner that remembers which jobs it was given and marks them as its own,
/// as a remote runner does.
class _Spy implements SchedulerRunner {
  new(this.id, this._inner, this._jobs, {this.refuses = const {}});

  @override
  final String id;
  final LocalRunner _inner;
  final JobRepository _jobs;

  /// The step kinds it refuses.
  final Set<String> refuses;

  /// Capabilities it has besides those of the inner runner.
  final extra = <Capability>{};

  /// The jobs it was given.
  final launched = <String>[];

  @override
  Set<Capability> get capabilities => {..._inner.capabilities, ...extra};

  @override
  int get slots => _inner.slots;

  @override
  bool accepts(Iterable<String> stepKinds) => !stepKinds.any(refuses.contains);

  @override
  Future<void> launch(String jobId) async {
    launched.add(jobId);
    await _inner.launch(jobId);
    if (id == localRunnerId) return;
    final job = (await _jobs.get(jobId))!;
    await _jobs.updateJob(job.copyWith(runnerId: id));
  }

  @override
  Future<void> whenFinished(String jobId) => _inner.whenFinished(jobId);
}

/// A place that cancels the jobs it holds.
class _Remote implements RemoteJobs {
  new(this.handled);

  final Set<String> handled;
  final asked = <String>[];

  @override
  Future<bool> cancel(String id) async {
    asked.add(id);
    return handled.contains(id);
  }
}

class _PairedRunners implements PairedRunners {
  new(this.runners);

  final List<PairedRunner> runners;
  int reads = 0;

  @override
  Future<List<PairedRunner>> pairedRunners() async {
    reads++;
    return runners;
  }
}
