import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);
  final expires = created.add(approvalLifetime);
  final record = ApprovalRecord(
    id: 'apr_1',
    projectId: 'prj_1',
    action: GateAction.prodRelease,
    sha: 'a' * 40,
    version: '1.2.3+45',
    runId: 'run_1',
    jobId: 'job_1',
    createdAt: created,
    expiresAt: expires,
  );

  test('lives 24 hours', () {
    expect(approvalLifetime, const Duration(hours: 24));
  });

  group('hasSameBinding', () {
    ApprovalRecord changed({
      String? projectId,
      GateAction? action,
      String? sha,
      String? version,
      String? runId,
    }) => ApprovalRecord(
      id: 'apr_other',
      projectId: projectId ?? 'prj_1',
      action: action ?? GateAction.prodRelease,
      sha: sha ?? 'a' * 40,
      version: version ?? '1.2.3+45',
      runId: runId ?? 'run_1',
      createdAt: created,
      expiresAt: expires,
    );

    test('holds for the same project, action, commit, version and run', () {
      expect(record.hasSameBinding(changed()), isTrue);
    });

    test('fails when any one of them differs', () {
      expect(record.hasSameBinding(changed(projectId: 'prj_2')), isFalse);
      expect(record.hasSameBinding(changed(action: GateAction.push)), isFalse);
      expect(record.hasSameBinding(changed(sha: 'b' * 40)), isFalse);
      expect(record.hasSameBinding(changed(version: '1.2.3+46')), isFalse);
      expect(record.hasSameBinding(changed(runId: 'run_2')), isFalse);
    });

    test('ignores the job that asked', () {
      final other = ApprovalRecord(
        id: 'apr_other',
        projectId: 'prj_1',
        action: GateAction.prodRelease,
        sha: 'a' * 40,
        version: '1.2.3+45',
        runId: 'run_1',
        jobId: 'job_2',
        createdAt: created,
        expiresAt: expires,
      );

      expect(record.hasSameBinding(other), isTrue);
    });
  });

  group('isDueAt', () {
    test('is true once the time is up, and only while pending', () {
      expect(
        record.isDueAt(expires.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(record.isDueAt(expires), isTrue);
      expect(record.isDueAt(expires.add(const Duration(days: 1))), isTrue);
      final approved = record.settled(
        state: ApprovalState.approved,
        at: created,
      );
      expect(approved.isDueAt(expires.add(const Duration(days: 1))), isFalse);
    });
  });

  test('settled keeps the binding and records the decision', () {
    const by = DecidedBy(
      tokenId: 'tok_1',
      name: 'Mac',
      kind: DeviceTokenKind.app,
    );
    final at = created.add(const Duration(hours: 1));

    final denied = record.settled(
      state: ApprovalState.denied,
      at: at,
      by: by,
      reason: 'no',
    );

    expect(denied.hasSameBinding(record), isTrue);
    expect(denied.id, record.id);
    expect(denied.state, ApprovalState.denied);
    expect(denied.decidedAt, at);
    expect(denied.decidedBy, by);
    expect(denied.reason, 'no');
    expect(denied.createdAt, created);
    expect(denied.expiresAt, expires);
    expect(denied.jobId, 'job_1');
  });

  test('toApi names the action by its wire name', () {
    final api = record.toApi();

    expect(api.action, 'prod_release');
    expect(api.state, ApprovalState.pending);
    expect(api.version, '1.2.3+45');
    expect(api.runId, 'run_1');
    expect(api.jobId, 'job_1');
    expect(api.createdAt, created);
    expect(api.expiresAt, expires);
    expect(api.decidedBy, isNull);
  });

  test('compares by value', () {
    final other = ApprovalRecord(
      id: 'apr_1',
      projectId: 'prj_1',
      action: GateAction.prodRelease,
      sha: 'a' * 40,
      version: '1.2.3+45',
      runId: 'run_1',
      jobId: 'job_1',
      createdAt: created,
      expiresAt: expires,
    );

    expect(record, other);
    expect(
      record,
      isNot(record.settled(state: ApprovalState.approved, at: created)),
    );
  });
}
