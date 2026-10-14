import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const request = GateRequest(
    action: GateAction.prodRelease,
    projectId: 'prj_1',
    sha: 'a',
    jobId: 'job_1',
    version: '1.2.3',
  );

  test('every action has the name D-13 gives it on the wire', () {
    expect(
      {for (final action in GateAction.values) action.wire},
      {
        'prod_release',
        'prod_patch',
        'store_submission',
        'push',
        'merge',
        'delete',
      },
    );
    expect(GateAction.fromWire('push'), GateAction.push);
    expect(GateAction.fromWire('ship'), isNull);
  });

  test('a request compares by value', () {
    expect(
      request,
      const GateRequest(
        action: GateAction.prodRelease,
        projectId: 'prj_1',
        sha: 'a',
        jobId: 'job_1',
        version: '1.2.3',
      ),
    );
  });

  test(
    'the gate of an engine without approvals never lets a job through',
    () async {
      final decision = await const PendingApprovalGate().check(request);

      expect(decision, isA<GatePending>());
      expect((decision as GatePending).approvalId, isNull);
    },
  );

  test('a fake gate answers as told and remembers the questions', () async {
    final gate = FakeApprovalGate();

    expect(await gate.check(request), isA<GatePending>());
    gate.decision = const GateApproved();
    expect(await gate.check(request), isA<GateApproved>());
    expect(gate.requests, [request, request]);
  });
}
