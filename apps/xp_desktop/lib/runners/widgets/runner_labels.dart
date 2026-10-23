import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';

/// The Run Sheet status of [runner] (Status guide, Runner): online and idle,
/// busy, draining (finishing its jobs before an update), offline, or offline
/// while it still holds leases (lost mid-job).
XpStatus runnerStatus(Runner runner) => switch (runner.activity) {
  RunnerActivity.idle => XpStatus.runnerIdle,
  RunnerActivity.busy => XpStatus.runnerBusy,
  RunnerActivity.updating => XpStatus.runnerUpdating,
  RunnerActivity.lost => XpStatus.runnerLost,
  RunnerActivity.offline || RunnerActivity.revoked => XpStatus.runnerOffline,
};

/// The label of [runnerStatus].
String runnerStatusLabel(Runner runner, AppLocalizations l10n) =>
    switch (runner.activity) {
      RunnerActivity.idle => l10n.runnerIdle,
      RunnerActivity.busy => l10n.runnerBusy(
        runner.jobIds.length,
        runner.slots,
      ),
      RunnerActivity.updating => l10n.runnerDraining,
      RunnerActivity.lost => l10n.runnerLost,
      RunnerActivity.offline => l10n.runnerOffline,
      RunnerActivity.revoked => l10n.runnerRevoked,
    };

/// What the machine reported about itself: `macos · arm64 · xp 1.0.0 · 12
/// cores`.
String runnerMachine(Runner runner, AppLocalizations l10n) => [
  ?runner.os,
  ?runner.arch,
  if (runner.version case final version?) 'xp $version',
  if (runner.cores case final cores?) l10n.runnerCores(cores),
].join(' · ');
