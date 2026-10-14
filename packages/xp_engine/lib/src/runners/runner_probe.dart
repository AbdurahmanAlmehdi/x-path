import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/toolchain/version_parsers.dart';

/// What the engine concluded from the results of a probe.
class ProbeFindings extends Equatable {
  /// Creates the findings.
  const new({required this.capabilities, this.operatingSystem});

  /// What the machine can do (D-19).
  final Set<Capability> capabilities;

  /// `macos` or `linux`, from `uname`; `null` for anything else.
  final String? operatingSystem;

  @override
  List<Object?> get props => [capabilities, operatingSystem];
}

/// The probe of a runner (D-19): commands the engine has the runner run, and
/// the rules that turn what they printed into capabilities.
///
/// The engine does not trust what a runner says about itself. It trusts only
/// what these commands print, and derives the capabilities exactly like
/// `LocalCapabilities` does for the machine the engine runs on:
///
/// - `flutter`: `git` runs, so the pinned SDK can be fetched.
/// - `android`: an Android SDK folder exists (`ANDROID_HOME`,
///   `ANDROID_SDK_ROOT` or a default place of Android Studio).
/// - `ios-sign`: macOS, with an Xcode selected (`xcode-select -p`) that
///   `xcodebuild -version` reports. Nothing touches a keychain; the
///   certificates and profiles are the runner owner's to keep in order, and
///   a job fails with a clear message when a signing identity is missing.
/// - `swift-linux`: Linux with `swift` installed.
class RunnerProbe {
  /// Creates the probe.
  const new();

  /// The shell script of the `android_sdk` command: exits 0 if a folder that
  /// has `platform-tools`, `cmdline-tools` or `build-tools` is one of the
  /// places `DirectoryAndroidSdk` looks in.
  static const androidSdkScript = r'''
for d in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
  [ -n "$d" ] || continue
  for m in platform-tools cmdline-tools build-tools; do
    [ -d "$d/$m" ] && exit 0
  done
done
exit 1
''';

  /// The commands to run, in order.
  List<ProbeCommand> get commands => const [
    ProbeCommand(id: 'os', executable: 'uname', arguments: ['-s']),
    ProbeCommand(id: 'git', executable: 'git', arguments: ['--version']),
    ProbeCommand(
      id: 'android_sdk',
      executable: 'sh',
      arguments: ['-c', androidSdkScript],
    ),
    ProbeCommand(
      id: 'xcode_select',
      executable: 'xcode-select',
      arguments: ['-p'],
      onlyOn: 'macos',
    ),
    // On a Mac without developer tools macOS answers `xcodebuild` with a
    // dialog, so it only runs once an Xcode is selected.
    ProbeCommand(
      id: 'xcodebuild',
      executable: 'xcodebuild',
      arguments: ['-version'],
      requires: 'xcode_select',
      onlyOn: 'macos',
    ),
    // `swift` on a Mac is a shim that can open the same dialog.
    ProbeCommand(
      id: 'swift',
      executable: 'swift',
      arguments: ['--version'],
      onlyOn: 'linux',
    ),
  ];

  /// What the runner can do, from its [results].
  ProbeFindings evaluate(List<ProbeResult> results) {
    final byId = {for (final result in results) result.id: result};
    bool succeeded(String id) => byId[id]?.succeeded ?? false;
    final uname = succeeded('os') ? byId['os']!.stdout.trim() : null;
    final os = switch (uname) {
      'Darwin' => 'macos',
      'Linux' => 'linux',
      _ => null,
    };
    final xcode =
        os == 'macos' &&
        succeeded('xcode_select') &&
        succeeded('xcodebuild') &&
        parseXcodeVersion(byId['xcodebuild']!.stdout) != null;
    return ProbeFindings(
      operatingSystem: os,
      capabilities: {
        if (succeeded('git')) Capability.flutter,
        if (succeeded('android_sdk')) Capability.android,
        if (xcode) Capability.iosSign,
        if (os == 'linux' && succeeded('swift')) Capability.swiftLinux,
      },
    );
  }
}
