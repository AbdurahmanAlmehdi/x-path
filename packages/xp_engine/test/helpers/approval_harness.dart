import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// A device token of [kind] for tests.
DeviceToken tokenOf(DeviceTokenKind kind, {String? name}) => DeviceToken(
  id: 'tok_${kind.name}',
  name: name ?? '${kind.name} device',
  kind: kind,
  hash: 'hash',
  createdAt: DateTime.utc(2026),
);

/// The commit gates ask about.
const approvalSha = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

/// What a job of the demo project asks at a gate.
GateRequest gateRequest({
  GateAction action = GateAction.prodRelease,
  String sha = approvalSha,
  String? version = '1.2.3+45',
  String jobId = 'job_1',
  String projectId = 'prj_1',
}) => GateRequest(
  action: action,
  projectId: projectId,
  sha: sha,
  version: version,
  jobId: jobId,
);

/// An [ApprovalService] over fakes.
class ApprovalHarness {
  new _({
    required this.approvals,
    required this.gates,
    required this.projects,
    required this.jobs,
    required this.events,
    required this.clock,
    required this.resumed,
    required this.service,
  });

  static Future<ApprovalHarness> create({
    ApprovalRepository? approvals,
    GateConfigRepository? gates,
    ProjectRepository? projects,
  }) async {
    final clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    final repository = approvals ?? InMemoryApprovalRepository();
    final configs = gates ?? InMemoryGateConfigRepository();
    final known = projects ?? InMemoryProjectRepository();
    if (projects == null) {
      await known.add(
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
    }
    final jobs = InMemoryJobRepository();
    final events = InMemoryEventLog(clock: clock);
    final resumed = <String>[];
    return ApprovalHarness._(
      approvals: repository,
      gates: configs,
      projects: known,
      jobs: jobs,
      events: events,
      clock: clock,
      resumed: resumed,
      service: ApprovalService(
        approvals: repository,
        gates: configs,
        projects: known,
        jobs: jobs,
        events: events,
        clock: clock,
        resume: (projectId) async => resumed.add(projectId),
        random: _Counting(),
      ),
    );
  }

  final ApprovalRepository approvals;
  final GateConfigRepository gates;
  final ProjectRepository projects;
  final InMemoryJobRepository jobs;
  final InMemoryEventLog events;
  final ManualClock clock;

  /// The projects whose waiting jobs the service asked to resume.
  final List<String> resumed;
  final ApprovalService service;

  /// The events logged so far.
  Future<List<EngineEvent>> logged() async {
    final seen = <EngineEvent>[];
    final subscription = events
        .subscribe(after: 0)
        .listen((entry) => seen.add(entry.event));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return seen;
  }
}

/// A random source whose bytes count up, so that ids differ and are stable.
class _Counting implements Random {
  var _next = 0;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1000) / 1000;

  @override
  int nextInt(int max) => _next++ % max;
}
