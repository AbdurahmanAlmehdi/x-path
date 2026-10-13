import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// The plists that carry literal versions must say what the pubspec says, or
/// the store build is not the version the owner meant
/// (`check_version_files_in_sync`, R:92-103).
class VersionSyncCheck extends GuardCheck {
  /// Creates the check.
  const new();

  @override
  GuardCheckName get name => GuardCheckName.versionSync;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final state = await request.versions();
    final want = state.pubspec;
    final wrong = state.plistsOutOfSync(want);
    if (wrong.isEmpty) {
      final literal = state.plists.where((plist) => plist.literal).length;
      return passed(
        literal == 0
            ? '${state.pubspecPath} says $want; no plist carries a literal '
                  'version.'
            : '${state.pubspecPath} and $literal plist(s) say $want.',
      );
    }
    return failed(
      [for (final plist in wrong) _disagreement(state.pubspecPath, want, plist)]
          .join('\n'),
      fix: 'Write the version into every version file with version.bump.',
    );
  }

  static String _disagreement(
    String pubspecPath,
    AppVersion want,
    PlistVersion plist,
  ) {
    final has = '${plist.shortVersion} ${plist.buildNumber}';
    final wanted = '${want.name} ${want.build ?? ''}';
    return "${plist.path} says '$has' but $pubspecPath says '$wanted'.";
  }
}
