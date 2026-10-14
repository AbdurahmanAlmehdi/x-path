import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/step_context.dart';

void main() {
  late FakeApprovalGate gate;
  late GateStep step;
  const input = GateInput(
    action: GateAction.prodRelease,
    projectId: 'prj_1',
    sha: 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
    version: '1.2.3+45',
  );

  setUp(() {
    gate = FakeApprovalGate();
    step = GateStep(gate);
  });

  test('is the gate step, with no side effect', () {
    expect(step.kind, 'gate');
    expect(step.sideEffectOf(input), isFalse);
  });

  test('stores its input and result', () {
    expect(step.decodeInput(step.encodeInput(input)), input);
    expect(
      GateInput.fromJson(const {'action': 'push', 'projectId': 'p', 'sha': 's'})
          .version,
      isNull,
    );
    expect(step.encodeInput(input), {
      'action': 'prod_release',
      'projectId': 'prj_1',
      'sha': 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
      'version': '1.2.3+45',
    });
    expect(step.encodeResult(const GateResult()), isEmpty);
    expect(const GateResult().props, isEmpty);
  });

  test('refuses an action that is not a gate', () {
    expect(
      () => GateInput.fromJson(const {
        'action': 'ship',
        'projectId': 'p',
        'sha': 's',
      }),
      throwsFormatException,
    );
  });

  test('asks the gate for the action, project, commit and version', () async {
    gate.decision = const GateApproved();

    final outcome = await step.run(input, NoProcessContext());

    expect(outcome, isA<StepSucceeded<GateResult>>());
    expect(
      gate.requests.single,
      const GateRequest(
        action: GateAction.prodRelease,
        projectId: 'prj_1',
        sha: 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
        version: '1.2.3+45',
        jobId: 'job_1',
      ),
    );
  });

  test('waits while nobody decided, and says what for', () async {
    gate.decision = const GatePending(approvalId: 'apr_1');

    final outcome = await step.run(input, NoProcessContext());

    expect(
      outcome,
      isA<StepWaiting>().having(
        (o) => o.reason,
        'reason',
        'Waiting for the owner to approve prod_release 1.2.3+45 on '
            'a1a1a1a1a1a1 (approval apr_1).',
      ),
    );
  });

  test('waits without an approval id or a version too', () async {
    const bare = GateInput(action: GateAction.push, projectId: 'p', sha: 'abc');

    final outcome = await step.run(bare, NoProcessContext());

    expect(
      (outcome as StepWaiting).reason,
      'Waiting for the owner to approve push on abc.',
    );
  });

  test('fails when the owner denied or the approval expired', () async {
    gate.decision = const GateDenied('Denied from the app.');

    final outcome = await step.run(input, NoProcessContext());

    expect(
      outcome,
      isA<StepFailed>().having(
        (o) => o.message,
        'message',
        'The owner did not approve prod_release 1.2.3+45 on a1a1a1a1a1a1: '
            'Denied from the app.',
      ),
    );
  });
}
