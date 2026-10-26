import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/steps/step.dart';

/// Why omarchy-apple-dev cannot build the iOS app of a job on Linux (ADR
/// 0014), from the planned [steps] of the job and its [app] (what the scan
/// found, `AppProfile.iosLinuxLimits`, and its extensions): one reason for
/// each thing the job uses that Linux iOS builds lack, with the work that
/// would lift it, led by [iosLinuxOff] when the owner turned Linux iOS
/// builds off for the app (`AppProfile.iosLinux`). Empty when nothing rules
/// Linux out.
///
/// The dispatcher narrows a job with reasons to `ios-sign` (a Mac), at plan
/// time, so that no job fails on Linux part-way through. Each case is
/// removed once omarchy-apple-dev can build it and XPath pins that commit.
List<String> iosLinuxLimits(List<StepPlan> steps, AppProfile app) {
  final reasons = <String>{if (!app.iosLinux) iosLinuxOff};
  for (final StepPlan(:kind, :input) in steps) {
    switch (kind) {
      case 'build.ios' || 'ios.stripAndReexport':
        if (input['flavor'] case final String flavor) {
          reasons.add(flavorsLimit([flavor]));
        }
        if (input['target'] case final String target) {
          reasons.add(
            'the flavor builds $target, and Linux iOS builds build '
            'lib/main.dart only (omarchy-apple-dev: entry points)',
          );
        }
        if (kind == 'ios.stripAndReexport') {
          reasons.add(
            'the job strips frameworks after the build, which XPath does not '
            'do on Linux yet',
          );
        }
        if (kind == 'build.ios' && input['linuxSigning'] == null) {
          reasons.add(
            'the flavor has no Apple Distribution identity with an App Store '
            'Connect API key assigned, which Linux runners sign with (xp '
            'credentials add --kind apple_distribution)',
          );
        }
      case 'shorebird.release' || 'shorebird.patch'
          when input['platform'] == 'ios':
        reasons.add(
          'the job uses Shorebird iOS, which needs macOS (Shorebird iOS on '
          'Linux is not decided)',
        );
      case 'command':
        reasons.addAll(_commandLimits(input));
    }
  }
  reasons.addAll(app.iosLinuxLimits);
  if (app.iosAppExtensions.isNotEmpty) {
    reasons.add(extensionsLimit(app.iosAppExtensions));
  }
  return reasons.toList();
}

/// Why an app whose owner turned Linux iOS builds off builds on a Mac.
const iosLinuxOff = 'Linux iOS builds are turned off for this app';

/// Why Linux iOS builds cannot build an app with the Flutter [flavors]: one
/// a job builds, or all a scan found.
String flavorsLimit(List<String> flavors) =>
    'the app uses the flavor${flavors.length == 1 ? '' : 's'} '
    '${flavors.join(', ')}, which Linux iOS builds do not support yet '
    '(omarchy-apple-dev: flavors)';

/// Why Linux iOS builds cannot build an app with the app [extensions].
String extensionsLimit(List<String> extensions) =>
    'the app has the app extension${extensions.length == 1 ? '' : 's'} '
    '${extensions.join(', ')}, which Linux iOS builds do not support yet '
    '(omarchy-apple-dev: app extensions)';

/// What a `command` step uses that Linux iOS builds lack: the iOS Simulator
/// (`xcrun simctl`, `--simulator`, an `iphonesimulator` SDK or destination),
/// or a debug or profile build of the iOS app.
List<String> _commandLimits(Map<String, dynamic> input) {
  final words = [
    if (input['executable'] case final String executable) executable,
    for (final argument in input['arguments'] as List? ?? const [])
      if (argument is String) argument,
  ];
  bool has(bool Function(String word) test) => words.any(test);
  final simulator = has(
    (word) =>
        word == 'simctl' ||
        word == '--simulator' ||
        word.toLowerCase().contains('iphonesimulator') ||
        word.contains('iOS Simulator'),
  );
  final iosBuild =
      has((word) => word == 'flutter' || word.endsWith('/flutter')) &&
      has((word) => word == 'build') &&
      has((word) => word == 'ios' || word == 'ipa');
  final limits = <String>[];
  if (simulator) {
    limits.add(
      'the job uses the iOS Simulator, which needs macOS (Linux workflows '
      'test on an Android emulator)',
    );
  }
  for (final mode in const ['debug', 'profile']) {
    if (iosBuild && has((word) => word == '--$mode')) {
      limits.add(
        'the job makes a $mode build of the iOS app, and Linux iOS builds '
        'are release builds only',
      );
    }
  }
  return limits;
}
