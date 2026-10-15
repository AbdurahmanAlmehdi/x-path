import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/job_fixtures.dart';

Approval _asking(String action, {String? version = '5.4.1+3283'}) => Approval(
  id: 'apr_x',
  projectId: 'prj_1',
  action: action,
  sha: sha,
  version: version,
  state: ApprovalState.pending,
  createdAt: pendingApproval.createdAt,
  expiresAt: pendingApproval.expiresAt,
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('every action has a title', () {
    expect(
      l10n.approvalTitle(_asking('prod_release')),
      'Release 5.4.1 (3283) to the stores',
    );
    expect(l10n.approvalTitle(_asking('prod_patch')), 'Patch 5.4.1 (3283)');
    expect(l10n.approvalTitle(_asking('push')), 'Push 5.4.1 (3283) to GitHub');
    expect(
      l10n.approvalTitle(_asking('merge')),
      'Merge the release PR of 5.4.1 (3283)',
    );
    expect(
      l10n.approvalTitle(_asking('delete')),
      'Approve the delete of 5.4.1 (3283)',
    );
    expect(
      l10n.approvalTitle(_asking('delete', version: null)),
      'Approve the delete',
    );
  });

  test('every action says what approving does', () {
    String consequence(String action) => l10n.approvalConsequence(
      _asking(action),
      flavor: 'prod',
      bundleId: 'com.sixdtec.mata',
    );
    expect(
      consequence('prod_release'),
      'XPath builds 5.4.1 (3283) from 9a3bc0d and releases it to the stores. '
      'It goes out as prod · com.sixdtec.mata.',
    );
    expect(
      consequence('prod_patch'),
      startsWith('XPath publishes a Shorebird'),
    );
    expect(consequence('push'), startsWith('XPath pushes the release commit'));
    expect(consequence('merge'), contains('into the base branch'));
    expect(consequence('delete'), contains('on 9a3bc0d'));
    expect(consequence('rename'), 'The job goes on with its rename.');
    expect(
      l10n.approvalConsequence(_asking('store_submission', version: null)),
      'XPath uploads the builds made from 9a3bc0d and submits 9a3bc0d for '
      'store review.',
    );
  });

  test('every state has a label and a status', () {
    for (final state in ApprovalState.values) {
      expect(l10n.approvalState(state), isNotEmpty);
      expect(approvalStatus(state), isA<XpStatus>());
    }
  });
}
