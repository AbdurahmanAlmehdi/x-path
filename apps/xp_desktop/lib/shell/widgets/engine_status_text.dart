import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The Run Sheet status of an engine connection. Connecting turns like
/// reconnecting; a refused token reads as unreachable (its own label says
/// why).
XpStatus engineXpStatus(EngineStatus status) => switch (status) {
  EngineStatus.connected => XpStatus.engineConnected,
  EngineStatus.connecting ||
  EngineStatus.reconnecting => XpStatus.engineReconnecting,
  EngineStatus.unreachable ||
  EngineStatus.rejected => XpStatus.engineUnreachable,
  EngineStatus.secretsLocked => XpStatus.engineSecretsLocked,
};

/// The label of an engine connection status.
String engineStatusLabel(AppLocalizations l10n, EngineStatus status) =>
    switch (status) {
      EngineStatus.connecting => l10n.statusConnecting,
      EngineStatus.connected => l10n.statusConnected,
      EngineStatus.reconnecting => l10n.statusReconnecting,
      EngineStatus.unreachable => l10n.statusUnreachable,
      EngineStatus.secretsLocked => l10n.statusSecretsLocked,
      EngineStatus.rejected => l10n.statusRejected,
    };
