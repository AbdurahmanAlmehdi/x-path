import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The status an approval in [state] shows.
XpStatus approvalStatus(ApprovalState state) => switch (state) {
  ApprovalState.pending => XpStatus.approvalPending,
  ApprovalState.approved => XpStatus.approvalApproved,
  ApprovalState.denied => XpStatus.approvalDenied,
  ApprovalState.expired => XpStatus.approvalExpired,
};

/// Whether less than an hour is left: the countdown turns `caution`.
bool expiresSoon(Approval approval, DateTime now) =>
    approval.expiresAt.difference(now) < const Duration(hours: 1);

extension ApprovalLabels on AppLocalizations {
  /// What an approval in [state] is called.
  String approvalState(ApprovalState state) => switch (state) {
    ApprovalState.pending => approvalPending,
    ApprovalState.approved => approvalApproved,
    ApprovalState.denied => approvalDenied,
    ApprovalState.expired => approvalExpired,
  };

  /// What [approval] asks for, in one line: `Submit 5.4.1 (3283) to the
  /// stores`.
  String approvalTitle(Approval approval) {
    final version = approval.version == null
        ? null
        : pubspecLabel(approval.version!);
    return switch ((approval.action, version)) {
      ('prod_release', final String version) => approvalTitleRelease(version),
      ('prod_patch', final String version) => approvalTitlePatch(version),
      ('store_submission', final String version) => approvalTitleSubmit(
        version,
      ),
      ('push', final String version) => approvalTitlePush(version),
      ('merge', final String version) => approvalTitleMerge(version),
      (final action, final String version) => approvalTitleOther(
        gateAction(action),
        version,
      ),
      (final action, null) => approvalTitleBare(gateAction(action)),
    };
  }

  /// What happens if the owner approves [approval] ("If you approve…").
  String approvalConsequence(
    Approval approval, {
    String? flavor,
    String? bundleId,
    String? baseBranch,
  }) {
    final sha = shortSha(approval.sha);
    final version = approval.version == null
        ? sha
        : pubspecLabel(approval.version!);
    final target = [?flavor, ?bundleId].join(' · ');
    final (text, shipped) = switch (approval.action) {
      'prod_release' => (approvalIfRelease(version, sha), true),
      'prod_patch' => (approvalIfPatch(version, sha), true),
      'store_submission' => (approvalIfSubmit(version, sha), true),
      'push' => (approvalIfPush(version, sha), false),
      'merge' => (
        approvalIfMerge(version, baseBranch ?? approvalBaseBranch),
        false,
      ),
      'delete' => (approvalIfDelete(sha), false),
      _ => (approvalIfOther(gateAction(approval.action)), false),
    };
    return shipped && target.isNotEmpty
        ? '$text ${approvalIfTarget(target)}'
        : text;
  }
}
