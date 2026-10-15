import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';

/// The name of [category].
String categoryName(StorageCategory category, AppLocalizations l10n) =>
    switch (category) {
      StorageCategory.artifacts => l10n.storageArtifacts,
      StorageCategory.logs => l10n.storageLogs,
      StorageCategory.worktrees => l10n.storageWorktrees,
      StorageCategory.mirrors => l10n.storageMirrors,
      StorageCategory.flutter => l10n.storageFlutter,
    };

/// What housekeeping gives back of [category] under [retention].
String categoryRule(
  StorageCategory category,
  RetentionSettings retention,
  AppLocalizations l10n,
) => switch (category) {
  StorageCategory.artifacts => l10n.storageArtifactsRule(
    retention.keepPerFlavor,
  ),
  StorageCategory.logs => l10n.storageLogsRule(retention.logDays),
  StorageCategory.worktrees => l10n.storageWorktreesRule,
  StorageCategory.mirrors => l10n.storageMirrorsRule,
  StorageCategory.flutter => l10n.storageFlutterRule,
};
