import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';

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
  late ApprovalHarness h;
  late List<_ManualTimer> timers;
  late List<Duration> periods;
  late List<Object> errors;

  ApprovalSweeper sweeper({ApprovalService? service}) => ApprovalSweeper(
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
    h = await ApprovalHarness.create();
    timers = [];
    periods = [];
    errors = [];
  });

  test('sweeps at once on start, then every minute', () async {
    await h.service.check(gateRequest());
    h.clock.advance(approvalLifetime);
    final sweeper0 = sweeper();

    await sweeper0.start();

    expect(sweeper0.isRunning, isTrue);
    expect(periods, [const Duration(minutes: 1)]);
    expect((await h.service.list()).single.state, ApprovalState.expired);
    expect(h.resumed, ['prj_1']);

    await h.service.check(gateRequest(sha: 'b' * 40));
    h.clock.advance(approvalLifetime);
    timers.single.fire();
    await pumpEventQueue();

    expect((await h.logged()).whereType<ApprovalExpired>(), hasLength(2));
  });

  test('starts only once', () async {
    final started = sweeper();

    await started.start();
    await started.start();

    expect(timers, hasLength(1));
  });

  test('stops, and can start again', () async {
    final stopped = sweeper();
    await stopped.start();

    stopped.stop();

    expect(stopped.isRunning, isFalse);
    expect(timers.single.isActive, isFalse);
    await stopped.start();
    expect(timers, hasLength(2));
  });

  test('stopping before starting does nothing', () {
    expect(() => sweeper().stop(), returnsNormally);
  });

  test('tells onError about a failed sweep and goes on', () async {
    final failing = await ApprovalHarness.create(approvals: _Failing());
    final failed = sweeper(service: failing.service);

    await failed.start();
    await failed.runNow();

    expect(errors, hasLength(2));
    expect(errors.first, isA<StateError>());
  });

  test('does not fail without an onError', () async {
    final failing = await ApprovalHarness.create(approvals: _Failing());
    final quiet = ApprovalSweeper(
      service: failing.service,
      timers: (period, callback) => _ManualTimer(callback),
    );

    await expectLater(quiet.runNow(), completes);
  });

  test('does not run two sweeps at once', () async {
    final blocked = _Blocking();
    final slow = await ApprovalHarness.create(approvals: blocked);
    final slowSweeper = sweeper(service: slow.service);

    final first = slowSweeper.runNow();
    await slowSweeper.runNow();
    blocked.release.complete();
    await first;

    expect(blocked.calls, 1);
  });
}

class _Failing extends InMemoryApprovalRepository {
  @override
  Future<List<ApprovalRecord>> expireDue(
    DateTime now, {
    required String reason,
    String? id,
  }) async => throw StateError('disk on fire');
}

class _Blocking extends InMemoryApprovalRepository {
  final release = Completer<void>();
  int calls = 0;

  @override
  Future<List<ApprovalRecord>> expireDue(
    DateTime now, {
    required String reason,
    String? id,
  }) async {
    calls++;
    await release.future;
    return const [];
  }
}
