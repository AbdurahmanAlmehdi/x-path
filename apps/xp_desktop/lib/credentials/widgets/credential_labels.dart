import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

export 'package:xp_desktop/credentials/flavor_target.dart';

/// The kinds a flavor can be given a named credential of: every kind but
/// the engine's one GitHub token.
final List<CredentialKind> namedKinds = [
  for (final kind in CredentialKind.values)
    if (kind.isNamed) kind,
];

/// The name of a credential kind.
String credentialKindLabel(AppLocalizations l10n, CredentialKind kind) =>
    switch (kind) {
      CredentialKind.ascKey => l10n.kindAscKey,
      CredentialKind.appleId => l10n.kindAppleId,
      CredentialKind.appleDistribution => l10n.kindAppleDistribution,
      CredentialKind.playSa => l10n.kindPlaySa,
      CredentialKind.firebaseSa => l10n.kindFirebaseSa,
      CredentialKind.keystore => l10n.kindKeystore,
      CredentialKind.shorebird => l10n.kindShorebird,
      CredentialKind.github => l10n.kindGithub,
      CredentialKind.slack => l10n.kindSlack,
    };

/// The status token and label of what a check found.
(XpStatus, String) credentialStatusLabel(
  AppLocalizations l10n,
  CredentialStatus status,
) => switch (status) {
  CredentialStatus.verified => (
    XpStatus.credentialVerified,
    l10n.credentialVerified,
  ),
  CredentialStatus.rejected => (
    XpStatus.credentialExpired,
    l10n.credentialRejected,
  ),
  CredentialStatus.unverified || CredentialStatus.unreachable => (
    XpStatus.credentialExpiring,
    l10n.credentialUnchecked,
  ),
};

/// What the checks of [statuses] add up to: rejected if one is, verified if
/// all are, `null` when there is none.
CredentialStatus? worstStatus(Iterable<CredentialStatus> statuses) {
  if (statuses.isEmpty) return null;
  if (statuses.contains(CredentialStatus.rejected)) {
    return CredentialStatus.rejected;
  }
  return statuses.every((status) => status == CredentialStatus.verified)
      ? CredentialStatus.verified
      : CredentialStatus.unverified;
}

/// Where a credential is used: the project, the app (when it is not the
/// root one) and the flavor.
String usageLabel(CredentialUsage usage) => [
  usage.project ?? usage.projectId,
  if (usage.app != '.') usage.app,
  usage.flavor,
].join(' · ');

/// What a check found, with why it refused and what to do about it.
class CredentialStatusView extends StatelessWidget {
  const new(this.status, {this.message, this.fix, super.key});

  final CredentialStatus status;
  final String? message;
  final String? fix;

  @override
  Widget build(BuildContext context) {
    final (token, label) = credentialStatusLabel(context.l10n, status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        XpStatusLabel(token, label),
        if (message case final message?)
          Text(
            [message, ?fix].join(' '),
            style: context.xpType.caption.copyWith(
              color: context.xpColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
