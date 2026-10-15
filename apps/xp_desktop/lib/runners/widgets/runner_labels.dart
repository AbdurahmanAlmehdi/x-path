import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';

/// The Run Sheet status of [runner] (Status guide, Runner): online and idle,
/// busy, draining (finishing its jobs before an update), offline, or offline
/// while it still holds leases (lost mid-job).
XpStatus runnerStatus(Runner runner) => switch (runner.status) {
  RunnerStatus.online when runner.jobIds.isEmpty => XpStatus.runnerIdle,
  RunnerStatus.online => XpStatus.runnerBusy,
  RunnerStatus.draining => XpStatus.runnerUpdating,
  RunnerStatus.offline when runner.jobIds.isNotEmpty => XpStatus.runnerLost,
  RunnerStatus.offline || RunnerStatus.revoked => XpStatus.runnerOffline,
};

/// The label of [runnerStatus].
String runnerStatusLabel(Runner runner, AppLocalizations l10n) =>
    switch (runner.status) {
      RunnerStatus.online when runner.jobIds.isEmpty => l10n.runnerIdle,
      RunnerStatus.online => l10n.runnerBusy(
        runner.jobIds.length,
        runner.slots,
      ),
      RunnerStatus.draining => l10n.runnerDraining,
      RunnerStatus.offline when runner.jobIds.isNotEmpty => l10n.runnerLost,
      RunnerStatus.offline => l10n.runnerOffline,
      RunnerStatus.revoked => l10n.runnerRevoked,
    };

/// What the machine reported about itself: `macos · arm64 · xp 1.0.0 · 12
/// cores`.
String runnerMachine(Runner runner, AppLocalizations l10n) => [
  ?runner.os,
  ?runner.arch,
  if (runner.version case final version?) 'xp $version',
  if (runner.cores case final cores?) l10n.runnerCores(cores),
].join(' · ');
