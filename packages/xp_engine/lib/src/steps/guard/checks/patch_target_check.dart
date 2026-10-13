import 'package:xp_engine/src/steps/guard/checks/patch_release.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/steps/guard/guard_ports.dart';

/// A prod patch must name the exact release it patches. `latest` is whichever
/// release was cut last, and more than one can be live (`guard_patch_target`,
/// R:149-155).
///
/// With Shorebird release data the check also proves that the release exists,
/// and says which Flutter version the patch will use (D-20).
class PatchTargetCheck extends GuardCheck {
  /// Creates the check. Without Shorebird data only the tag is looked for.
  const new({this._shorebird});

  final ShorebirdReleases? _shorebird;

  @override
  GuardCheckName get name => GuardCheckName.patchTarget;

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
    final warnings = <String>[
      if (!tagged) 'No tag $tag; check that $release is the release you mean.',
    ];
    final facts = ['Patch target $release.'];

    final appId = request.input.shorebirdAppId;
    final shorebird = _shorebird;
    if (shorebird != null && appId != null) {
      final releases = await shorebird.releases(appId);
      if (releases == null) {
        warnings.add('Could not list the Shorebird releases of $appId.');
      } else {
        final match = releases.where((r) => r.version == release).firstOrNull;
        if (match == null) {
          final known = releases.map((r) => r.version).join(', ');
          return failed(
            'Shorebird has no release $release for $appId. It has: '
            '${releases.isEmpty ? 'none' : known}.',
            fix: 'Patch a release that was made with shorebird release.',
          );
        }
        facts.add(
          'The patch will use Flutter ${match.flutterVersion}, the version '
          'of the release.',
        );
      }
    }

    if (warnings.isNotEmpty) return warned([...warnings, ...facts].join('\n'));
    return passed(facts.join('\n'));
  }
}
