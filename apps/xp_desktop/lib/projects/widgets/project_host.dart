import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';

/// Where a project's repository lives, in words (ADR 0015).
extension ProjectHost on Project {
  /// The git host, such as `bitbucket.org`, or "local repository" for a
  /// `file://` origin.
  String hostLabel(AppLocalizations l10n) =>
      isLocal ? l10n.projectHostLocal : host;
}
