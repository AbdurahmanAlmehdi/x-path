import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// XPath's cache of Flutter SDKs: one folder per exact version under [root],
/// normally `<data-dir>/toolchains/flutter` (D-20).
///
/// An SDK is installed with `git clone --depth 1 --branch <version>` of the
/// Flutter repository into a temporary folder of the cache, which is then
/// renamed to the version, so a cache folder is never half cloned. Running
/// `flutter --version --machine` in it precaches the Dart SDK and the Flutter
/// tool, so that the first build does not have to.
class GitFlutterInstaller implements FlutterInstaller {
  /// Creates an installer that keeps SDKs under [root].
  const new({
    required this.root,
    required this._runner,
    this.repositoryUrl = 'https://github.com/flutter/flutter.git',
    this.gitExecutable = 'git',
    this.cloneTimeout = const Duration(minutes: 30),
    this.precacheTimeout = const Duration(minutes: 30),
  });

  /// The cache folder.
  final String root;

  /// The Flutter repository to clone.
  final String repositoryUrl;

  /// The `git` program.
  final String gitExecutable;

  /// How long the clone may take.
  final Duration cloneTimeout;

  /// How long the precache may take.
  final Duration precacheTimeout;

  final ProcessRunner _runner;

  static const _environment = {
    // A missing tag must fail, not ask for a password.
    'GIT_TERMINAL_PROMPT': '0',
    'CI': 'true',
    'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    'BOT': 'true',
  };

  @override
  String pathFor(String version) => p.join(root, _checked(version));

  @override
  Future<bool> isInstalled(String version) async =>
      File(p.join(pathFor(version), 'bin', 'flutter')).existsSync();

  @override
  Future<void> install(String version) async {
    final target = pathFor(version);
    Directory(root).createSync(recursive: true);
    final temporary = Directory(root).createTempSync('.install-$version-');
    try {
      await _clone(version, temporary.path);
      try {
        temporary.renameSync(target);
      } on FileSystemException catch (error) {
        // Another install of the same version finished first.
        if (!await isInstalled(version)) {
          throw FlutterInstallException(
            'Cannot move the SDK into the cache: ${error.message}',
          );
        }
        return;
      }
    } finally {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    }
    try {
      await _precache(target);
    } on FlutterInstallException {
      Directory(target).deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<void> _clone(String version, String into) async {
    final output = await _run(gitExecutable, [
      'clone',
      '--depth',
      '1',
      '--branch',
      version,
      '--single-branch',
      repositoryUrl,
      into,
    ], cloneTimeout);
    if (output.exitCode != 0) {
      throw FlutterInstallException(
        'git clone of Flutter $version failed (exit ${output.exitCode}): '
        '${_last(output.stderr)}',
      );
    }
  }

  Future<void> _precache(String sdk) async {
    final output = await _run(p.join(sdk, 'bin', 'flutter'), [
      '--version',
      '--machine',
    ], precacheTimeout);
    if (output.exitCode != 0) {
      throw FlutterInstallException(
        'flutter --version failed (exit ${output.exitCode}): '
        '${_last(output.stderr)}',
      );
    }
  }

  Future<ProcessOutput> _run(
    String executable,
    List<String> arguments,
    Duration timeout,
  ) async {
    try {
      return await _runner.run(
        executable,
        arguments,
        environment: _environment,
        timeout: timeout,
      );
    } on ProcessStartException catch (error) {
      throw FlutterInstallException('Cannot run $executable: ${error.message}');
    } on TimeoutException {
      throw FlutterInstallException(
        '$executable did not finish within ${timeout.inMinutes} minutes.',
      );
    }
  }

  static String _checked(String version) {
    if (!isExactFlutterVersion(version)) {
      throw ArgumentError.value(
        version,
        'version',
        'must be an exact Flutter version such as 3.47.6',
      );
    }
    return version;
  }

  static String _last(String text) {
    final lines = text.trim().split('\n');
    return lines.last.trim();
  }
}
