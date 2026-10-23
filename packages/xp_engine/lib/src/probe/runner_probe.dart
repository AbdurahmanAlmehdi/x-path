import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/toolchain/version_parsers.dart';

/// What the engine concluded from the results of a probe.
class ProbeFindings extends Equatable {
  /// Creates the findings.
  const new({
    required this.capabilities,
    this.operatingSystem,
    this.missing = const [],
  });

  /// What the machine can do (D-19).
  final Set<Capability> capabilities;

  /// `macos` or `linux`, from `uname`; `null` for anything else.
  final String? operatingSystem;

  /// What it cannot do, why, and what gives it. A capability that cannot
  /// exist on its operating system (`ios-sign` on Linux, `swift-linux` on
  /// macOS) is not listed. One capability can be listed more than once, once
  /// for each thing it lacks.
  final List<MissingCapability> missing;

  @override
  List<Object?> get props => [capabilities, operatingSystem, missing];
}

/// The probe of a machine (D-19): commands that ask for versions or look for
/// folders, and the rules that turn what they printed into capabilities.
///
/// The engine does not trust what a runner says about itself. It trusts only
/// what these commands print. The engine probes its own machine
/// (`LocalCapabilities`) and `xp runner doctor` probes the runner's with the
/// same commands and rules, so the three never disagree:
///
/// - `flutter`: `git` runs, so the pinned SDK can be fetched. On Linux the
///   SDK download also needs `curl`, `unzip` and `xz`.
/// - `android`: an Android SDK folder exists (`ANDROID_HOME`,
///   `ANDROID_SDK_ROOT` or a default place of Android Studio), and a JDK
///   [minimumJdk] or later runs: `JAVA_HOME`, the one Android Studio brings,
///   or `java` on the `PATH`, as Flutter looks for it.
/// - `ios-sign`: macOS, with an Xcode selected (`xcode-select -p`) that
///   `xcodebuild -version` reports. Nothing touches a keychain; the
///   certificates and profiles are the runner owner's to keep in order, and
///   a job fails with a clear message when a signing identity is missing.
/// - `swift-linux`: Linux with `swift` installed.
///
/// Each capability it does not find comes with the reason, taken from the
/// command that failed, and the fix (`ProbeFindings.missing`).
class RunnerProbe {
  /// Creates the probe.
  const new();

  /// The oldest JDK the Android Gradle plugin accepts.
  static const minimumJdk = 17;

  /// The shell script of the `android_sdk` command: exits 0 if a folder that
  /// has `platform-tools`, `cmdline-tools` or `build-tools` is one of the
  /// places Flutter looks in.
  static const androidSdkScript = r'''
for d in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
  [ -n "$d" ] || continue
  for m in platform-tools cmdline-tools build-tools; do
    [ -d "$d/$m" ] && exit 0
  done
done
exit 1
''';

  /// The shell script of the `java` command: runs `java -version` of the
  /// first JDK found in `JAVA_HOME`, Android Studio or the `PATH`. When none
  /// is found, the shell exits 127.
  static const javaScript = r'''
for j in "${JAVA_HOME:+$JAVA_HOME/bin/java}" \
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" \
  "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" \
  "/opt/android-studio/jbr/bin/java" "$HOME/android-studio/jbr/bin/java"; do
  [ -n "$j" ] && [ -x "$j" ] && exec "$j" -version
done
exec java -version
''';

  /// The shell script of the `flutter_tools` command (Linux): exits 1 and
  /// prints the names of the tools the Flutter SDK download needs that are
  /// not installed.
  static const flutterToolsScript = r'''
missing=
for tool in curl unzip xz; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] && exit 0
echo $missing
exit 1
''';

  /// The Debian package of each tool of [flutterToolsScript].
  static const _packages = {'curl': 'curl', 'unzip': 'unzip', 'xz': 'xz-utils'};

  /// The commands to run, in order.
  List<ProbeCommand> get commands => const [
    ProbeCommand(id: 'os', executable: 'uname', arguments: ['-s']),
    ProbeCommand(id: 'git', executable: 'git', arguments: ['--version']),
    ProbeCommand(
      id: 'flutter_tools',
      executable: 'sh',
      arguments: ['-c', flutterToolsScript],
      onlyOn: 'linux',
    ),
    ProbeCommand(
      id: 'android_sdk',
      executable: 'sh',
      arguments: ['-c', androidSdkScript],
    ),
    ProbeCommand(id: 'java', executable: 'sh', arguments: ['-c', javaScript]),
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

  /// What the machine can do, from its [results].
  ProbeFindings evaluate(List<ProbeResult> results) {
    final byId = {for (final result in results) result.id: result};
    final uname = byId['os']?.succeeded ?? false
        ? byId['os']!.stdout.trim()
        : null;
    final os = switch (uname) {
      'Darwin' => 'macos',
      'Linux' => 'linux',
      _ => null,
    };
    final linux = os == 'linux';
    final missing = <MissingCapability>[];
    void lacks(Capability capability, String reason, String fix) => missing.add(
      MissingCapability(capability: capability.wire, reason: reason, fix: fix),
    );

    final git = _problem(byId['git'], 'git');
    if (git != null) {
      lacks(
        Capability.flutter,
        'no git: $git',
        linux ? 'install git (apt-get install git)' : 'install git',
      );
    }
    final tools = linux ? _flutterToolsProblem(byId['flutter_tools']) : null;
    if (tools != null) {
      final (reason, packages) = tools;
      lacks(
        Capability.flutter,
        reason,
        'install ${packages.length == 1 ? 'it' : 'them'} '
        '(apt-get install ${packages.join(' ')})',
      );
    }

    final sdk = byId['android_sdk']?.succeeded ?? false;
    if (!sdk) {
      final home = os == 'macos' ? '~/Library/Android/sdk' : '~/Android/Sdk';
      lacks(
        Capability.android,
        'no Android SDK in ANDROID_HOME, ANDROID_SDK_ROOT or $home',
        'install the Android command-line tools or set ANDROID_HOME',
      );
    }
    final jdk = _jdkProblem(byId['java']);
    if (jdk != null) {
      lacks(
        Capability.android,
        'no JDK: $jdk',
        linux
            ? 'install JDK $minimumJdk (apt-get install '
                  'openjdk-$minimumJdk-jdk-headless) or set JAVA_HOME'
            : 'install JDK $minimumJdk or set JAVA_HOME',
      );
    }

    String? xcode;
    if (os == 'macos') {
      final selected = _problem(byId['xcode_select'], 'xcode-select');
      if (selected != null) {
        xcode = selected;
        lacks(
          Capability.iosSign,
          'no Xcode selected: $selected',
          'install Xcode and choose it in Xcode, Settings, Locations, '
              'Command Line Tools',
        );
      } else {
        final build = byId['xcodebuild'];
        xcode =
            _problem(build, 'xcodebuild') ??
            (parseXcodeVersion(build!.stdout) == null
                ? 'xcodebuild printed no Xcode version'
                : null);
        if (xcode != null) {
          lacks(
            Capability.iosSign,
            'Xcode does not answer: $xcode',
            'open Xcode once to finish its setup and accept its licence',
          );
        }
      }
    }

    final swift = linux ? _problem(byId['swift'], 'swift') : null;
    if (swift != null) {
      lacks(
        Capability.swiftLinux,
        'no Swift: $swift',
        'install Swift for Linux from swift.org',
      );
    }

    return ProbeFindings(
      operatingSystem: os,
      capabilities: {
        if (git == null && tools == null) Capability.flutter,
        if (sdk && jdk == null) Capability.android,
        if (os == 'macos' && xcode == null) Capability.iosSign,
        if (linux && swift == null) Capability.swiftLinux,
      },
      missing: missing,
    );
  }

  /// Why the command [what] did not succeed, or `null` when it did.
  static String? _problem(ProbeResult? result, String what) => switch (result) {
    null || ProbeResult(status: ProbeStatus.skipped) => '$what was not checked',
    ProbeResult(status: ProbeStatus.notStarted) => '$what not found',
    ProbeResult(status: ProbeStatus.timedOut) => '$what did not answer in time',
    ProbeResult(exitCode: 0) => null,
    // What a shell answers for a program it cannot find.
    ProbeResult(exitCode: 127) => '$what not found',
    final result =>
      _firstLine(result.stderr) ??
          _firstLine(result.stdout) ??
          '$what exited with ${result.exitCode}',
  };

  /// Why the JDK does not count, or `null` when it does.
  static String? _jdkProblem(ProbeResult? result) {
    final problem = _problem(result, 'java');
    if (problem != null) return problem;
    // `java -version` prints on standard error.
    final match = RegExp(r'version "(\d+)(?:\.(\d+))?')
        .firstMatch('${result!.stderr}\n${result.stdout}');
    if (match == null) return 'java printed no version';
    // Before 9, Java 8 called itself 1.8.
    final major = int.parse(
      match.group(1) == '1' ? match.group(2) ?? '1' : match.group(1)!,
    );
    if (major < minimumJdk) return 'JDK $major is older than $minimumJdk';
    return null;
  }

  /// Why the tools of the Flutter SDK download do not count, and the
  /// packages that give them; `null` when they count.
  static (String, List<String>)? _flutterToolsProblem(ProbeResult? result) {
    if (result?.succeeded ?? false) return null;
    final names = result?.status == ProbeStatus.exited && result!.exitCode == 1
        ? result.stdout.split(RegExp(r'\s+')).where(_packages.containsKey)
        : const <String>[];
    if (names.isEmpty) {
      return (
        'no curl, unzip or xz: they could not be checked '
            '(${_problem(result, 'sh')})',
        _packages.values.toList(),
      );
    }
    return (
      'no ${names.join(', ')}: the Flutter SDK download needs '
          '${names.length == 1 ? 'it' : 'them'}',
      [for (final name in names) _packages[name]!],
    );
  }

  /// The first line of [text] that is not blank, without its full stop: a
  /// reason is one sentence the caller ends.
  static String? _firstLine(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim().replaceFirst(RegExp(r'\.+$'), '');
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
