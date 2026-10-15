import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;

/// Runs [executable] with [arguments] and gives its result. Tests pass a
/// fake.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// A tool the engine on this Mac uses.
enum Tool {
  /// Xcode, for iOS builds and uploads. Found with `xcode-select -p`.
  xcode(required: true),

  /// git, for the engine's mirrors.
  git(required: true),

  /// fvm, which picks the Flutter of each project. Without it the engine
  /// downloads the pinned Flutter itself (D-20).
  fvm(required: false),

  /// The GitHub CLI, whose token the engine can import.
  gh(required: false),

  /// Shorebird, for over-the-air patches.
  shorebird(required: false);

  new({required this.required});

  /// Whether a release cannot be built without it.
  final bool required;
}

/// Whether one [tool] was found.
class ToolCheck extends Equatable {
  /// Creates the result.
  const new(this.tool, {this.path});

  /// The tool.
  final Tool tool;

  /// Where it is, or `null` if it was not found.
  final String? path;

  /// Whether it was found.
  bool get found => path != null;

  @override
  List<Object?> get props => [tool, path];
}

/// Checks which tools are on this Mac.
abstract interface class ToolChecker {
  /// One result per [Tool], in their order.
  Future<List<ToolCheck>> check();
}

/// The folders the engine's LaunchAgent searches, as `xpd install-service`
/// writes them (`defaultServicePath`), for the home folder [home].
List<String> serviceSearchPath(String home) => [
  '/opt/homebrew/bin',
  '/opt/homebrew/sbin',
  '/usr/local/bin',
  p.join(home, '.shorebird', 'bin'),
  p.join(home, '.pub-cache', 'bin'),
  p.join(home, 'fvm', 'default', 'bin'),
  '/usr/bin',
  '/bin',
  '/usr/sbin',
  '/sbin',
];

/// The [ToolChecker] of this Mac. It looks for the executables in the
/// folders of [searchPath] and asks `xcode-select -p` for Xcode. It never
/// runs `xcodebuild` or `/usr/bin/git`: on a Mac without developer tools
/// those answer with a dialog that offers to install them.
class PathToolChecker implements ToolChecker {
  /// Creates the checker.
  const new({required this.searchPath, this._run = Process.run});

  /// The folders to look in, in order.
  final List<String> searchPath;

  final RunProcess _run;

  Future<String?> _developerDirectory() async {
    try {
      final result = await _run('/usr/bin/xcode-select', ['-p']);
      final path = (result.stdout as String).trim();
      return result.exitCode == 0 && path.isNotEmpty ? path : null;
    } on ProcessException {
      return null;
    }
  }

  String? _find(String name, {required bool developerTools}) {
    for (final directory in searchPath) {
      // `/usr/bin/git` is a shim of the developer tools.
      if (!developerTools && directory == '/usr/bin' && name == 'git') {
        continue;
      }
      final path = p.join(directory, name);
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// The Command Line Tools alone are not Xcode: they cannot build for iOS.
  String? _xcode(String? developer) =>
      developer == null || developer.contains('CommandLineTools')
      ? null
      : developer;

  @override
  Future<List<ToolCheck>> check() async {
    final developer = await _developerDirectory();
    return [
      for (final tool in Tool.values)
        ToolCheck(
          tool,
          path: tool == Tool.xcode
              ? _xcode(developer)
              : _find(tool.name, developerTools: developer != null),
        ),
    ];
  }
}
