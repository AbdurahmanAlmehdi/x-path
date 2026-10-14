import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final at = DateTime.utc(2026, 10, 13, 9);
  Approval approval(ApprovalState state, {DecidedBy? by}) => Approval(
    id: 'apr_1',
    projectId: 'prj_1',
    action: 'push',
    sha: 'a' * 40,
    state: state,
    createdAt: at,
    expiresAt: at.add(approvalLifetime),
    decidedBy: by,
  );

  test('each exception says what is wrong', () {
    expect(
      const ApprovalNotFoundException('apr_x').message,
      'There is no approval apr_x.',
    );
    expect(const ApprovalNotFoundException('apr_x').id, 'apr_x');
    expect(
      const ApprovalNotFoundException('apr_x').toString(),
      'ApprovalNotFoundException: There is no approval apr_x.',
    );
    expect(
      const ApprovalForbiddenException('no').toString(),
      'ApprovalForbiddenException: no',
    );
    expect(
      const ApprovalRequestException('bad').toString(),
      'ApprovalRequestException: bad',
    );
    expect(const ApprovalException('x').toString(), 'ApprovalException: x');
  });

  test('ApprovalAlreadyDecidedException names the winner', () {
    final exception = ApprovalAlreadyDecidedException(
      approval(
        ApprovalState.approved,
        by: const DecidedBy(
          tokenId: 'tok_1',
          name: 'Mac mini',
          kind: DeviceTokenKind.app,
        ),
      ),
    );

    expect(
      exception.message,
      'Approval apr_1 was approved by Mac mini (app) already: the first '
      'decision wins.',
    );
    expect(exception.approval.state, ApprovalState.approved);
    expect(exception.toString(), startsWith('ApprovalAlreadyDecidedException'));
  });

  test('ApprovalAlreadyDecidedException explains an expiry', () {
    final exception = ApprovalAlreadyDecidedException(
      approval(ApprovalState.expired),
    );

    expect(exception.message, contains('expired'));
    expect(exception.message, contains('counts as denied'));
  });

  test('ApprovalAlreadyDecidedException copes with a missing decider', () {
    final exception = ApprovalAlreadyDecidedException(
      approval(ApprovalState.denied),
    );

    expect(
      exception.message,
      'Approval apr_1 was denied already: the first decision wins.',
    );
  });
}
