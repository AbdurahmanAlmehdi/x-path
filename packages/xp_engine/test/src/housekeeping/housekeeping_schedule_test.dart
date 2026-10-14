import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/housekeeping_harness.dart';

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
  late HousekeepingHarness h;
  late List<_ManualTimer> timers;
  late List<Duration> periods;
  late List<Object> errors;

  HousekeepingSchedule schedule({HousekeepingService? service}) =>
      HousekeepingSchedule(
        service: service ?? h.service,
        clock: h.clock,
        onError: (error, _) => errors.add(error),
        timers: (period, callback) {
          periods.add(period);
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );

  Future<void> addOldJob() async {
    await h.addBuild(id: 'old', days: 100, names: const []);
    h.files.logs['old'] = 1;
  }

  setUp(() async {
    h = await HousekeepingHarness.create();
    timers = [];
    periods = [];
    errors = [];
  });

  test('prunes at the start when it never did, then every day', () async {
    await addOldJob();
    final running = schedule();

    await running.start();

    expect(running.isRunning, isTrue);
    expect(periods, [const Duration(hours: 24)]);
    expect(h.files.logs, isEmpty);
    expect(await h.service.lastLogPrune(), h.clock.now());

    await addOldJob();
    timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(h.files.logs, isEmpty);
  });

  test('does not prune at the start when it did a few hours ago', () async {
    await h.settings.saveLogPrune(h.ago(hours: 5));
    await addOldJob();

    await schedule().start();

    expect(h.files.logs, isNotEmpty);
  });

  test('prunes at the start when the last pruning is a day old', () async {
    await h.settings.saveLogPrune(h.ago(days: 1));
    await addOldJob();

    await schedule().start();

    expect(h.files.logs, isEmpty);
  });

  test('starting twice does not start a second timer', () async {
    final running = schedule();

    await running.start();
    await running.start();

    expect(timers, hasLength(1));
  });

  test('stop cancels the timer', () async {
    final running = schedule();
    await running.start();

    running.stop();

    expect(running.isRunning, isFalse);
    expect(timers.single.isActive, isFalse);
    running.stop();
  });

  test('a failing pruning is reported and the schedule goes on', () async {
    await addOldJob();
    h.files.failOn = 'logs old';
    final running = schedule();

    await running.start();

    expect(errors.single, isA<HousekeepingException>());
    expect(running.isRunning, isTrue);
  });

  test('a pruning does not start while another is under way', () async {
    await addOldJob();
    final gate = Completer<void>();
    final slow = _SlowService(h, gate.future);
    final running = schedule(service: slow);

    final first = running.runNow();
    await running.runNow();
    gate.complete();
    await first;

    expect(slow.prunes, 1);
  });

  test('not knowing when it last ran is reported', () async {
    final running = schedule(service: _UnreadableService(h));

    await running.start();

    expect(errors.single, isA<StateError>());
    expect(running.isRunning, isTrue);
  });
}

class _SlowService extends HousekeepingService {
  new(HousekeepingHarness h, this._gate)
    : super(
        planner: h.planner,
        settings: h.settings,
        artifacts: h.artifacts,
        store: h.store,
        jobs: h.jobs,
        files: h.files,
        clock: h.clock,
      );

  final Future<void> _gate;
  int prunes = 0;

  @override
  Future<FreedCategory> pruneLogs() {
    prunes++;
    return _gate.then((_) => super.pruneLogs());
  }
}

class _UnreadableService extends HousekeepingService {
  new(HousekeepingHarness h)
    : super(
        planner: h.planner,
        settings: h.settings,
        artifacts: h.artifacts,
        store: h.store,
        jobs: h.jobs,
        files: h.files,
        clock: h.clock,
      );

  @override
  Future<DateTime?> lastLogPrune() async => throw StateError('disk on fire');
}
