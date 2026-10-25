import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/job_harness.dart';

/// A production release meets its gate: the job stops, holding nothing, until
/// the owner decides from the app or the CLI; an agent cannot.
void main() {
  late InMemoryJobRepository jobs;
  late InMemoryRunRepository runs;
  late InMemoryApprovalRepository approvals;
  late InMemoryGateConfigRepository gates;
  late InMemoryEventLog events;
  late ManualClock clock;
  late JobHarness harness;
  late Scheduler scheduler;
  late ApprovalService service;
  late String jobId;

  final app = tokenOf(DeviceTokenKind.app, name: 'Mac mini');
  final cli = tokenOf(DeviceTokenKind.cli);
  final mcp = tokenOf(DeviceTokenKind.mcp);

  Future<String> pendingId() async {
    final pending = await service.list(state: ApprovalState.pending);
    return pending.single.id;
  }

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    jobs = InMemoryJobRepository();
    runs = InMemoryRunRepository();
    approvals = InMemoryApprovalRepository();
    gates = InMemoryGateConfigRepository();
    events = InMemoryEventLog(clock: clock);
    final projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '1',
        githubRepoId: 1,
        fullName: 'o/r',
        remote: 'x',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
    );
    service = ApprovalService(
      approvals: approvals,
      gates: gates,
      projects: projects,
      jobs: jobs,
      events: events,
      clock: clock,
      resume: (projectId) => scheduler.resumeWaiting(projectId: projectId),
    );
    harness = JobHarness.create(
      repository: jobs,
      extraSteps: [GateStep(service)],
    );
    scheduler = Scheduler(
      runner: harness.runner,
      records: jobs,
      runs: runs,
      events: events,
      runners: [
        LocalRunner(
          jobs: harness.runner,
          capabilities: const {Capability.flutter},
          slots: 2,
        ),
      ],
      onError: (error, _) => harness.errors.add(error),
    );
    // A production release: a gate in front of the step that publishes.
    await runs.create(
      RunRecord(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_prod',
        workflowVersionId: 'wfv_1',
        sha: approvalSha,
        locksProject: true,
        version: '1.2.3',
        build: 45,
        createdAt: clock.now(),
      ),
    );
    final job = await harness.runner.create(
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      sha: approvalSha,
      runId: 'run_1',
      name: 'Prepare prod',
      steps: [
        StepPlan.of(
          GateStep(service),
          const GateInput(
            action: GateAction.prodRelease,
            projectId: 'prj_1',
            sha: approvalSha,
            version: '1.2.3+45',
          ),
        ),
        harness.command('publish'),
      ],
    );
    jobId = job.id;
    await scheduler.pump();
    await _until(harness, JobState.waitingForApproval, jobId);
  });

  Future<Job> job() => harness.runner.get(jobId);

  test('stops at the gate with a pending approval and runs nothing', () async {
    final stopped = await job();

    expect(stopped.state, JobState.waitingForApproval);
    expect(stopped.message, contains('Waiting for the owner to approve'));
    expect(harness.supervisor.specs, isEmpty);
    final approval = (await service.list()).single;
    expect(approval.state, ApprovalState.pending);
    expect(approval.action, 'prod_release');
    expect(approval.version, '1.2.3+45');
    expect(approval.runId, 'run_1');
    expect(approval.jobId, jobId);
    expect(stopped.message, contains(approval.id));
  });

  test('goes on once an app token approves', () async {
    final id = await pendingId();

    final approved = await service.decide(id, approve: true, by: app);
    await _until(harness, JobState.succeeded, jobId);

    expect(approved.state, ApprovalState.approved);
    expect(harness.supervisor.specs.map((spec) => spec.executable), [
      'publish',
    ]);
    expect((await service.list()).single.state, ApprovalState.approved);
  });

  test('goes on once a cli token approves', () async {
    await service.decide(await pendingId(), approve: true, by: cli);
    await _until(harness, JobState.succeeded, jobId);

    expect(harness.supervisor.specs, hasLength(1));
  });

  test('does not go on for an mcp token, which can only watch', () async {
    final id = await pendingId();

    await expectLater(
      service.decide(id, approve: true, by: mcp),
      throwsA(isA<ApprovalForbiddenException>()),
    );
    await scheduler.pump();

    expect((await job()).state, JobState.waitingForApproval);
    expect((await service.get(id)).state, ApprovalState.pending);
    expect(harness.supervisor.specs, isEmpty);
  });

  test("fails with the owner's reason once a denial is recorded", () async {
    await service.decide(
      await pendingId(),
      approve: false,
      by: app,
      reason: 'wrong build',
    );
    final failed = await _until(harness, JobState.failed, jobId);

    expect(failed.message, contains('denied by Mac mini (app): wrong build'));
    expect(harness.supervisor.specs, isEmpty);
  });

  test('fails when 24 hours pass without a decision', () async {
    clock.advance(approvalLifetime);

    await service.sweep();
    final failed = await _until(harness, JobState.failed, jobId);

    expect(failed.message, contains('24 hours'));
    expect(failed.message, contains('expired'));
    expect(harness.supervisor.specs, isEmpty);
    final approval = (await service.list()).single;
    expect(approval.state, ApprovalState.expired);
    await expectLater(
      service.decide(approval.id, approve: true, by: app),
      throwsA(isA<ApprovalAlreadyDecidedException>()),
    );
  });

  test('goes on once an app token turns the gate off', () async {
    await service.setGates(
      'prj_1',
      const ProjectGates({'prod_release': false}),
      by: app,
    );
    await _until(harness, JobState.succeeded, jobId);

    expect(harness.supervisor.specs, hasLength(1));
  });

  test('stays waiting when a cli token tries to turn the gate off', () async {
    await expectLater(
      service.setGates(
        'prj_1',
        const ProjectGates({'prod_release': false}),
        by: cli,
      ),
      throwsA(isA<ApprovalForbiddenException>()),
    );
    await scheduler.pump();

    expect((await job()).state, JobState.waitingForApproval);
  });
}

Future<Job> _until(JobHarness harness, JobState state, String id) async {
  late Job latest;
  for (var i = 0; i < 2000; i++) {
    latest = await harness.runner.get(id);
    if (latest.state == state) return latest;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw StateError('Job $id never reached ${state.wire}: ${latest.state}.');
}
