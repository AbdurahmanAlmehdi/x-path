import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

/// A timer that does not tick by itself.
class _ManualTimer implements Timer {
  new(this.callback);

  final void Function(Timer timer) callback;

  @override
  bool isActive = true;

  @override
  int get tick => 0;

  @override
  void cancel() => isActive = false;

  void fire() => callback(this);
}

void main() {
  late RunnerHarness h;
  late List<_ManualTimer> timers;
  late List<Duration> periods;
  late List<Object> errors;

  LeaseSweeper sweeper() => LeaseSweeper(
    hub: h.hub,
    onError: (error, _) => errors.add(error),
    timers: (period, callback) {
      periods.add(period);
      final timer = _ManualTimer(callback);
      timers.add(timer);
      return timer;
    },
  );

  setUp(() async {
    h = await RunnerHarness.create();
    timers = [];
    periods = [];
    errors = [];
  });

  test('ends the leases that ran out, every ten seconds', () async {
    final runner = await h.online();
    final first = await h.job(needs: ['ios-sign']);
    await h.scheduler.pump();
    await runner.accept();
    h.clock.advance(const Duration(seconds: 90));
    await runner.heartbeat(const []);
    final started = sweeper();

    await started.start();
    await h.settle();

    expect(started.isRunning, isTrue);
    expect(periods, [const Duration(seconds: 10)]);
    final lost = await h.eventsOf<RunnerLeaseLost>();
    expect(lost.map((e) => e.jobId), [first]);

    // Another lease runs out later and the timer finds it.
    await runner.accept();
    h.clock.advance(const Duration(seconds: 90));
    await runner.heartbeat(const []);
    timers.single.fire();
    await h.settle();
    expect(await h.eventsOf<RunnerLeaseLost>(), hasLength(2));
  });

  test('starts only once, and stops', () async {
    final started = sweeper();

    await started.start();
    await started.start();
    expect(timers, hasLength(1));
    started.stop();

    expect(started.isRunning, isFalse);
    expect(timers.single.isActive, isFalse);
    started.stop();
    await started.start();
    expect(timers, hasLength(2));
  });

  test('does not sweep twice at once', () async {
    final jobs = _ControlledJobs();
    h = await RunnerHarness.create(jobRepository: jobs);
    final gate = Completer<void>();
    var sweeps = 0;
    jobs.onList = () async {
      sweeps++;
      await gate.future;
    };
    final started = sweeper();

    final first = started.runNow();
    await started.runNow();
    gate.complete();
    await first;

    expect(sweeps, 1);
  });

  test('reports a sweep that failed and goes on', () async {
    final jobs = _ControlledJobs();
    h = await RunnerHarness.create(jobRepository: jobs);
    jobs.onList = () async => throw StateError('disk on fire');
    final started = sweeper();

    await started.runNow();
    await started.runNow();

    expect(errors, hasLength(2));
    expect(errors.first, isA<StateError>());
  });

  test('works without anyone listening for errors', () async {
    final jobs = _ControlledJobs();
    h = await RunnerHarness.create(jobRepository: jobs);
    jobs.onList = () async => throw StateError('disk on fire');

    await LeaseSweeper(hub: h.hub).runNow();
  });
}

/// A job repository that does what the test says when jobs are listed.
class _ControlledJobs extends InMemoryJobRepository {
  Future<void> Function()? onList;

  @override
  Future<List<JobRecord>> list({required Set<JobState> states}) async {
    await onList?.call();
    return await super.list(states: states);
  }
}
