import 'dart:async';

import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/toolchain/tool_prober.dart';
import 'package:xp_engine/src/toolchain/tool_report.dart';

/// Whether an Android SDK is installed on this machine.
///
/// `xp_adapters` has the `dart:io` implementation: `ANDROID_HOME`,
/// `ANDROID_SDK_ROOT`, then the default places of Android Studio.
abstract interface class AndroidSdkLocator {
  /// The folder of the SDK, or `null` if there is none.
  Future<String?> locate();
}

/// An [AndroidSdkLocator] that finds [path], for tests.
class FakeAndroidSdkLocator implements AndroidSdkLocator {
  /// Creates a locator that finds [path], or no SDK for `null`.
  const new([this.path]);

  /// What it finds.
  final String? path;

  @override
  Future<String?> locate() async => path;
}

/// What this machine can do (D-19): the engine asks the tools instead of
/// trusting a setting.
///
/// - `flutter`: `git` runs, so the pinned SDK can be fetched (`fvm` or a
///   download into the cache, see `FlutterResolver`).
/// - `android`: an Android SDK is installed.
/// - `ios-sign`: macOS with an Xcode selected (`ToolProber.xcode`).
/// - `swift-linux`: Linux with `swift` installed.
class LocalCapabilities {
  /// Creates the probe.
  const new({
    required this._runner,
    required this._prober,
    required this._android,
    required this.isMacOS,
    this.timeout = const Duration(seconds: 30),
  });

  final ProcessRunner _runner;
  final ToolProber _prober;
  final AndroidSdkLocator _android;

  /// Whether this machine runs macOS.
  final bool isMacOS;

  /// How long `git` and `swift` have to answer.
  final Duration timeout;

  /// Probes the machine.
  Future<Set<Capability>> probe() async {
    final (git, swift, xcode, sdk) = await (
      _runs('git', const ['--version']),
      isMacOS ? Future.value(false) : _runs('swift', const ['--version']),
      _prober.xcode(),
      _android.locate(),
    ).wait;
    return {
      if (git) Capability.flutter,
      if (sdk != null) Capability.android,
      if (xcode.status == ToolStatus.available) Capability.iosSign,
      if (swift) Capability.swiftLinux,
    };
  }

  Future<bool> _runs(String executable, List<String> arguments) async {
    try {
      final output = await _runner.run(executable, arguments, timeout: timeout);
      return output.exitCode == 0;
    } on ProcessStartException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
