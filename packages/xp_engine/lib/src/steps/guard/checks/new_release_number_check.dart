import 'package:xp_engine/src/steps/guard/guard_check.dart';

/// A version that was released before cannot be released again, and an older
/// one cannot follow a newer one (`guard_new_release_number`, R:157-163;
/// `assert_version_unreleased`, L:143-159).
///
/// Reusing a marketing version leaves the earlier release unpatchable, and
/// the App Store has closed the train of every version below the live one.
/// The one tag that is not a reuse is this version and build on the commit
/// being released: that is the release's other platform.
class NewReleaseNumberCheck extends GuardCheck {
  /// Creates the check.
  const new();

  @override
  GuardCheckName get name => GuardCheckName.newReleaseNumber;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final version = (await request.versions()).pubspec;
    final tags = await request.releaseTags();
    final sha = request.target.sha;

    final reused = [
      for (final (:tag, :commit) in tags)
        if (tag.version == version.name &&
            !(!tag.isPatch && tag.build == version.build && commit == sha))
          tag.name,
    ];
    if (reused.isNotEmpty) {
      return failed(
        '${reused.first} already exists, so ${version.name} has shipped '
        'before.',
        fix: 'Bump to a higher version; the build number goes up on its own.',
      );
    }
    final released = tags.map((entry) => entry.tag.version);
    final last = released.isEmpty
        ? null
        : released.reduce((a, b) => a > b ? a : b);
    if (last != null && last > version.name) {
      return failed(
        '${version.name} is not higher than $last, which was released '
        'before.',
        fix: 'Bump to a version higher than $last.',
      );
    }
    return passed(
      last == null
          ? '${version.name} is the first release.'
          : '${version.name} is higher than the last release, $last.',
    );
  }
}
