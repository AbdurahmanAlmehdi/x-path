import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// Finds the Android SDK on this machine: `ANDROID_HOME`, then
/// `ANDROID_SDK_ROOT`, then the default places of Android Studio.
///
/// A folder counts when it has `platform-tools`, `cmdline-tools` or
/// `build-tools`: the SDK that `flutter build apk` needs.
class DirectoryAndroidSdk implements AndroidSdkLocator {
  /// Creates the locator.
  ///
  /// [environment] is the environment of the engine and [home] the home
  /// folder of its user.
  const new({required this.environment, required this.home});

  /// The environment variables.
  final Map<String, String> environment;

  /// The home folder, `null` if the engine has none.
  final String? home;

  @override
  Future<String?> locate() async {
    final candidates = [
      environment['ANDROID_HOME'],
      environment['ANDROID_SDK_ROOT'],
      if (home != null) ...[
        p.join(home!, 'Library', 'Android', 'sdk'),
        p.join(home!, 'Android', 'Sdk'),
      ],
    ];
    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) continue;
      for (final marker in const [
        'platform-tools',
        'cmdline-tools',
        'build-tools',
      ]) {
        if (Directory(p.join(candidate, marker)).existsSync()) {
          return candidate;
        }
      }
    }
    return null;
  }
}
