import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

/// What onboarding and the settings say of where `xp` stands, or `null`
/// when it is not linked (nothing to say yet).
(XpStatus, String)? cliLinkMessage(AppLocalizations l10n, CliLink? link) =>
    switch (link) {
      null || CliLink(state: CliLinkState.notLinked) => null,
      CliLink(state: CliLinkState.linked, :final path?, fellBack: true) => (
        XpStatus.credentialVerified,
        l10n.cliLinkedFallback(path),
      ),
      CliLink(state: CliLinkState.linked, :final path) => (
        XpStatus.credentialVerified,
        l10n.cliLinked(path ?? ''),
      ),
      CliLink(state: CliLinkState.elsewhere, :final path, :final pointsTo) => (
        XpStatus.scanWarning,
        l10n.cliElsewhere(path ?? '', pointsTo ?? ''),
      ),
      CliLink(state: CliLinkState.missingBinary) => (
        XpStatus.scanWarning,
        l10n.cliMissing,
      ),
      CliLink(state: CliLinkState.conflict, :final path) => (
        XpStatus.scanWarning,
        l10n.cliConflict(path ?? ''),
      ),
      CliLink(state: CliLinkState.failed, :final detail) => (
        XpStatus.scanError,
        l10n.cliFailed(detail ?? ''),
      ),
    };
