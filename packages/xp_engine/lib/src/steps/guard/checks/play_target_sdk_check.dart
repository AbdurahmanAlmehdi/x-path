import 'package:xp_engine/src/scan/gradle_parser.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/steps/guard/guard_ports.dart';

/// Google Play refuses an update whose `targetSdk` is below the level it
/// asks for (D-22). Reads the level from the Gradle scripts of the app.
class PlayTargetSdkCheck extends GuardCheck {
  /// Creates the check over [_play].
  const new(this._play);

  final PlayRequirements _play;

  // `targetSdk = 35`, `targetSdkVersion 34`, `targetSdkVersion(34)`.
  static final _targetSdk = RegExp(
    r'\btargetSdk(?:Version)?(?![A-Za-z0-9_])\s*[=(]?\s*(\d+)',
  );

  @override
  GuardCheckName get name => GuardCheckName.playTargetSdk;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final directory = request.target.inApp('android/app');
    final scripts = await _scripts(request, directory);
    if (scripts.isEmpty) return skipped('The app has no Android project.');

    final required = await _play.requiredTargetSdk();
    if (required == null) {
      return warned(
        'Could not read the target API level Google Play asks for.',
      );
    }
    final target = _targetOf(scripts);
    if (target == null) {
      return warned(
        'The target API level is not a number in the Gradle scripts (it comes '
        "from Flutter's default), so it cannot be compared with the $required "
        'that Google Play asks for.',
        fix:
            'Set targetSdk = $required (or higher) in android/app/build.gradle.',
      );
    }
    if (target < required) {
      return failed(
        'The app targets API $target; Google Play asks for $required or '
        'higher.',
        fix: 'Raise targetSdk to $required in android/app/build.gradle.',
      );
    }
    return passed(
      'The app targets API $target; Google Play asks for $required.',
    );
  }

  /// The Gradle scripts of the app, `build.gradle` first, without comments.
  Future<List<String>> _scripts(GuardRequest request, String directory) async {
    final files =
        [
          for (final entry in await request.workspace.list(directory))
            if (!entry.isDirectory &&
                (entry.name.endsWith('.gradle') ||
                    entry.name.endsWith('.gradle.kts')))
              entry.name,
        ]..sort(
          (a, b) =>
              _rank(a) - _rank(b) != 0 ? _rank(a) - _rank(b) : a.compareTo(b),
        );
    return [
      for (final file in files)
        withoutGradleComments(
          await request.workspace.read(joinScanPath(directory, file)) ?? '',
        ),
    ];
  }

  static int _rank(String file) => file.startsWith('build.gradle') ? 0 : 1;

  static int? _targetOf(List<String> scripts) {
    for (final script in scripts) {
      final match = _targetSdk.firstMatch(script);
      if (match != null) return int.parse(match[1]!);
    }
    return null;
  }
}
