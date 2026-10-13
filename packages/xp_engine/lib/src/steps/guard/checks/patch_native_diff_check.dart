import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/steps/guard/checks/patch_release.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';

/// Native changes cannot ship in an over-the-air patch: they fail at
/// runtime, not at build. Compares the commit being patched with the release
/// tag (`release_kind`, O:643-657).
class PatchNativeDiffCheck extends GuardCheck {
  /// Creates the check.
  const new();

  /// The folders of an app that hold native code, relative to the app.
  static const nativeFolders = ['android', 'ios', 'macos', 'linux', 'windows'];

  @override
  GuardCheckName get name => GuardCheckName.patchNativeDiff;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final (:release, :problem) = readPatchRelease(request.input.releaseVersion);
    if (release == null) {
      return failed(
        problem!,
        fix: 'Pass an exact release version, for example 5.4.1+3283.',
      );
    }
    final target = request.target;
    final tag = target.releaseModel.tagName(
      release.name,
      release.build!,
      scope: target.scope,
    );
    final tagged = (await request.git.listTags(target.mirror))
        .any((info) => info.name == tag);
    if (!tagged) {
      return failed(
        'No tag $tag, so there is nothing to compare the patch with. '
        'Refusing to patch blind.',
        fix: 'Tag the release commit, or patch a release that has a tag.',
      );
    }
    final changed = await request.git.changedFiles(
      target.mirror,
      from: tag,
      to: target.sha,
    );
    final native = [
      for (final path in changed)
        if (nativeFolders.any(
          (folder) =>
              path.startsWith('${joinScanPath(target.appPath, folder)}/'),
        ))
          path,
    ];
    if (native.isEmpty) {
      return passed('Dart and assets only since $tag: patch-eligible.');
    }
    return failed(
      'Native files changed since $tag:\n'
      '${native.map((path) => '  $path').join('\n')}',
      fix: 'This needs a full store release, not a patch.',
    );
  }
}
