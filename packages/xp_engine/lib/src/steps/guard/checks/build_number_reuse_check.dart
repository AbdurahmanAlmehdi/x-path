import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/versioning/store_build_numbers.dart';

/// Both stores reject a build number they have seen, and a tag records one
/// that was issued (D-11, D-22). This asks before the build, not after the
/// upload.
///
/// A tag for this version and build on the commit being released is the same
/// release (its other platform, or a resumed job), not a reuse.
class BuildNumberReuseCheck extends GuardCheck {
  /// Creates the check over [_stores].
  const new(this._stores);

  final StoreBuildNumbers _stores;

  @override
  GuardCheckName get name => GuardCheckName.buildNumberReuse;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final version = (await request.versions()).pubspec;
    final build = version.build;
    if (build == null) {
      return failed(
        'The pubspec version $version has no build number.',
        fix: 'Write one with version.bump.',
      );
    }
    final tags = await request.releaseTags();
    final sha = request.target.sha;
    final sameRelease = tags.any(
      (entry) =>
          entry.tag.version == version.name &&
          entry.tag.build == build &&
          entry.commit == sha,
    );
    if (sameRelease) {
      return passed(
        'Build $build is already tagged on this commit: same release.',
      );
    }
    final tagged = tags.where((entry) => entry.tag.build == build).firstOrNull;
    if (tagged != null) {
      return failed(
        'Build $build is already used by the tag ${tagged.tag.name}.',
        fix: 'Allocate a new build number; the stores reject a reused one.',
      );
    }
    final store = await _stores.lookup(
      iosBundleId: request.input.iosBundleId,
      androidAppId: request.input.androidAppId,
    );
    if (store == null) {
      return warned(
        'Could not read the build numbers from the stores; only the tags were '
        'checked, and build $build is not among them.',
      );
    }
    if (store.used.contains(build)) {
      return failed(
        'The store already has a build $build.',
        fix: 'Allocate a new build number; the stores reject a reused one.',
      );
    }
    return passed('Build $build is not used by the stores or the tags.');
  }
}
