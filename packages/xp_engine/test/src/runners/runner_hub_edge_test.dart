import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

/// A job repository that lets a test do something right after a job is saved.
class _HookedJobs extends InMemoryJobRepository {
  void Function(JobRecord job)? afterSave;

  @override
  Future<void> updateJob(JobRecord job) async {
    await super.updateJob(job);
    afterSave?.call(job);
  }
}

/// A log store whose files fail to close.
class _FailingCloseLogs implements JobLogStore {
  new(this._inner);

  final JobLogStore _inner;

  @override
  Future<JobLogWriter> open({
    required String jobId,
    required int ordinal,
    required String kind,
  }) async => _FailingWriter(
    await _inner.open(jobId: jobId, ordinal: ordinal, kind: kind),
  );

  @override
  Stream<LogLineFrame> read(String jobId, {int after = 0}) =>
      _inner.read(jobId, after: after);

  @override
  Future<int> head(String jobId) => _inner.head(jobId);
}

class _FailingWriter implements JobLogWriter {
  new(this._inner);

  final JobLogWriter _inner;

  @override
  String get path => _inner.path;

  @override
  Future<void> write(LogLineFrame line) => _inner.write(line);

  @override
  Future<void> close() async => throw StateError('disk on fire');
}

/// Runners that cannot be saved once [failing] is set.
class _FailingRunners implements RunnerRepository {
  new(this._inner);

  final RunnerRepository _inner;
  bool failing = false;

  @override
  Future<void> add(RunnerRecord runner) => _inner.add(runner);

  @override
  Future<RunnerRecord?> get(String id) => _inner.get(id);

  @override
  Future<RunnerRecord?> findByName(String name) => _inner.findByName(name);

  @override
  Future<RunnerRecord?> findByToken(String tokenId) =>
      _inner.findByToken(tokenId);

  @override
  Future<List<RunnerRecord>> list() => _inner.list();

  @override
  Future<void> update(RunnerRecord runner) async {
    if (failing) throw StateError('disk on fire');
    await _inner.update(runner);
  }
}

/// Runners whose `get` does what the test says before it answers.
class _ScriptedRunners implements RunnerRepository {
  new(this._inner);

  final RunnerRepository _inner;
  Future<RunnerRecord?> Function(RunnerRepository inner, String id)? onGet;

  @override
  Future<void> add(RunnerRecord runner) => _inner.add(runner);

  @override
  Future<RunnerRecord?> get(String id) async =>
      onGet == null ? await _inner.get(id) : await onGet!(_inner, id);

  @override
  Future<RunnerRecord?> findByName(String name) => _inner.findByName(name);

  @override
  Future<RunnerRecord?> findByToken(String tokenId) =>
      _inner.findByToken(tokenId);

  @override
  Future<List<RunnerRecord>> list() => _inner.list();

  @override
  Future<void> update(RunnerRecord runner) => _inner.update(runner);
}

void main() {
  test(
    'a job the engine ended is dropped from the lease when it lapses',
    () async {
      final h = await RunnerHarness.create();
      final runner = await h.online();
      final jobId = await h.job(needs: ['ios-sign']);
      await h.scheduler.pump();
      await runner.accept();
      // The engine's own cancel, which knows nothing of leases.
      await h.jobs.runner.cancel(jobId);

      h.clock.advance(const Duration(seconds: 90));
      await runner.heartbeat();
      await h.settle();

      expect(runner.cancels.single.reason, 'The lease ran out.');
      expect(h.hub.jobsOf(runner.id), isEmpty);
      expect(await h.state(jobId), JobState.cancelled);
      expect(h.errors, isEmpty);
    },
  );

  test('a job someone resumed meanwhile is left alone', () async {
    final jobs = _HookedJobs();
    Future<void>? resumed;
    final h = await RunnerHarness.create(jobRepository: jobs);
    final runner = await h.online();
    final jobId = await h.job(needs: ['ios-sign']);
    await h.scheduler.pump();
    await runner.accept();
    // Right after the hub marks the job interrupted, the owner resumes it.
    jobs.afterSave = (job) {
      if (job.state == JobState.interrupted) {
        jobs.afterSave = null;
        resumed = jobs.updateJob(job.copyWith(state: JobState.queued));
      }
    };

    h.clock.advance(const Duration(seconds: 90));
    await h.hub.sweep();
    await resumed;
    await h.settle();

    expect(h.errors, isEmpty);
    expect(await h.state(jobId), JobState.queued);
  });

  test('a lease whose files fail to close still ends', () async {
    final h = await RunnerHarness.create(
      hubLogs: (store) => JobLogs(store: _FailingCloseLogs(store)),
    );
    final runner = await h.online();
    final jobId = await h.job(needs: ['ios-sign']);
    await h.scheduler.pump();
    await runner.accept();
    await runner.chunk(1, ['a']);
    await runner.step(0, StepState.succeeded);

    await runner.done(JobState.succeeded, lastChunk: 1);

    expect(await h.state(jobId), JobState.succeeded);
    expect(h.errors.single, isA<StateError>());
    expect(h.hub.jobsOf(runner.id), isEmpty);
    // The slot is free: the lease finished although closing failed.
    await h.hub.whenFinished(jobId);
  });

  test('a failure while a frame is handled is reported, not thrown', () async {
    late _FailingRunners failing;
    final h = await RunnerHarness.create(
      wrapRunners: (inner) => failing = _FailingRunners(inner),
    );
    final runner = await h.pair();
    failing.failing = true;

    await runner.hello();

    expect(h.errors.single, isA<StateError>());
    expect(runner.link.sentOf<ProbeFrame>(), isEmpty);
    h.errors.clear();
  });

  test('a revoke that happens meanwhile is not written over', () async {
    late _ScriptedRunners runners;
    final h = await RunnerHarness.create(
      wrapRunners: (inner) => runners = _ScriptedRunners(inner),
    );
    final runner = await h.online();
    // The owner revokes between the runner's heartbeat and its save.
    runners.onGet = (inner, id) async {
      final stored = (await inner.get(id))!;
      await inner.update(stored.copyWith(revokedAt: h.clock.now()));
      return await inner.get(id);
    };

    await runner.heartbeat(const []);

    final stored = (await h.runners.get(runner.id))!;
    expect(stored.isRevoked, isTrue);
    expect(stored.lastHeartbeat, h.clock.now());
    expect(h.errors, isEmpty);
  });

  test('a runner that is gone from the store is reported', () async {
    late _ScriptedRunners runners;
    final h = await RunnerHarness.create(
      wrapRunners: (inner) => runners = _ScriptedRunners(inner),
    );
    final runner = await h.pair();
    runners.onGet = (inner, id) async => null;

    await runner.hello();

    expect(h.errors.single, isA<StateError>());
    h.errors.clear();
  });

  test('an accept that comes after the lease ran out is cancelled', () async {
    final h = await RunnerHarness.create();
    final runner = await h.online();
    await h.job(needs: ['ios-sign']);
    await h.scheduler.pump();

    h.clock.advance(const Duration(seconds: 90));
    await runner.accept();
    await h.settle();

    expect(runner.cancels.single.reason, 'The lease ran out.');
    expect(runner.cancels.single.leaseId, runner.offers.first.leaseId);
    expect(h.errors, isEmpty);
  });
}
