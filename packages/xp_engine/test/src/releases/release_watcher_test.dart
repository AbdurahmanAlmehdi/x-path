import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/release_harness.dart';

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
  late ReleaseHarness h;
  late List<_ManualTimer> timers;
  late List<Duration> periods;
  late List<Object> errors;

  ReleaseWatcher watcher({ReleaseService? service}) => ReleaseWatcher(
    events: h.events,
    service: service ?? h.service,
    onError: (error, _) => errors.add(error),
    timers: (period, callback) {
      periods.add(period);
      final timer = _ManualTimer(callback);
      timers.add(timer);
      return timer;
    },
  );

  setUp(() async {
    h = await ReleaseHarness.create();
    timers = [];
    periods = [];
    errors = [];
  });

  test('polls at once on start, then every minute', () async {
    final id = await h.open();
    await h.finishBuild(id);
    await h.service.sync(id);
    h.apple.reading = const StoreReading(
      state: StoreState.inReview,
      source: StatusSource.api,
      detail: 'IN_REVIEW',
    );
    h.play.reading = const StoreReading(
      state: StoreState.inReview,
      source: StatusSource.api,
      detail: 'IN_REVIEW',
    );
    final started = watcher();

    await started.start();

    expect(started.isRunning, isTrue);
    expect(periods, [const Duration(minutes: 1)]);
    expect((await h.record(id)).state, ReleaseState.inReview);

    h.clock.advance(const Duration(minutes: 11));
    timers.single.fire();
    await pumpEventQueue();

    expect(h.apple.reads, hasLength(2));
    await started.stop();
  });

  test('starts only once', () async {
    final started = watcher();

    await started.start();
    await started.start();

    expect(timers, hasLength(1));
    await started.stop();
  });

  test('brings a release up to date when its job changes', () async {
    final id = await h.open();
    final started = watcher();
    await started.start();

    final job = await h.addJob(id, [
      ('build.android', StepState.running, null),
    ]);
    h.events.append(
      JobStateChanged(jobId: job, projectId: 'prj_1', state: JobState.running),
    );
    await pumpEventQueue();

    expect((await h.record(id)).state, ReleaseState.building);

    await h.setStep(job, 0, StepState.succeeded);
    h.events.append(
      JobStepChanged(
        jobId: job,
        ordinal: 0,
        kind: 'build.android',
        state: StepState.succeeded,
      ),
    );
    h.events.append(const StreamOpened());
    await pumpEventQueue();

    expect(errors, isEmpty);
    await started.stop();
  });

  test('stops, and can start again', () async {
    final started = watcher();
    await started.start();

    await started.stop();

    expect(started.isRunning, isFalse);
    expect(timers.single.isActive, isFalse);
    await started.stop();
    await started.start();
    expect(timers, hasLength(2));
    await started.stop();
  });

  test('reports a failing poll and goes on', () async {
    final failing = ReleaseWatcher(
      events: h.events,
      service: _Failing(h),
      onError: (error, _) => errors.add(error),
      timers: (period, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await failing.start();
    timers.single.fire();
    await pumpEventQueue();

    expect(errors, hasLength(2));
    await failing.stop();
  });

  test('reports a failing sync and goes on', () async {
    final failing = ReleaseWatcher(
      events: h.events,
      service: _Failing(h),
      onError: (error, _) => errors.add(error),
      timers: (period, callback) => _ManualTimer(callback),
    );
    await failing.start();
    errors.clear();

    h.events.append(
      const JobStateChanged(
        jobId: 'job_1',
        projectId: 'prj_1',
        state: JobState.running,
      ),
    );
    await pumpEventQueue();

    expect(errors, hasLength(1));
    await failing.stop();
  });

  test('does not poll twice at once', () async {
    final slow = _Slow(h);
    final started = ReleaseWatcher(
      events: h.events,
      service: slow,
      onError: (error, _) => errors.add(error),
      timers: (period, callback) => _ManualTimer(callback),
    );

    final first = started.pollNow();
    await started.pollNow();
    slow.release.complete();
    await first;

    expect(slow.polls, 1);
  });
}

class _Failing extends ReleaseService {
  new(ReleaseHarness h)
    : super(
        releases: h.releases,
        jobs: h.jobs,
        runRecords: h.runs,
        runs: RunService(runs: h.runs, jobs: h.jobs, control: h.control),
        workflows: h.workflows,
        poller: ReleaseStatusPoller(sources: const [], clock: h.clock),
        events: h.events,
        clock: h.clock,
        dispatch: (_, _, _) => throw UnimplementedError(),
      );

  @override
  Future<int> pollDue() async => throw StateError('poll');

  @override
  Future<void> syncJob(String jobId) async => throw StateError('sync');
}

class _Slow extends ReleaseService {
  new(ReleaseHarness h)
    : super(
        releases: h.releases,
        jobs: h.jobs,
        runRecords: h.runs,
        runs: RunService(runs: h.runs, jobs: h.jobs, control: h.control),
        workflows: h.workflows,
        poller: ReleaseStatusPoller(sources: const [], clock: h.clock),
        events: h.events,
        clock: h.clock,
        dispatch: (_, _, _) => throw UnimplementedError(),
      );

  final Completer<void> release = Completer<void>();
  int polls = 0;

  @override
  Future<int> pollDue() async {
    polls++;
    await release.future;
    return 0;
  }
}
