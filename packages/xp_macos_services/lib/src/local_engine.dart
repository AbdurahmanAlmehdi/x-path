import 'dart:io';

import 'package:xp_macos_services/src/tool_checker.dart';

/// The engine the app bundles, run as the command line tool it is.
abstract interface class LocalEngine {
  /// Whether this build carries the engine (Phase 18b copies it in).
  bool get isBundled;

  /// Makes a device token of kind `app` called [name] with
  /// `xpd token create`, in the engine's default data folder (the one the
  /// LaunchAgent serves), and returns it. A running engine accepts it at
  /// once.
  ///
  /// Throws a [LocalEngineException] when the engine is missing or fails.
  Future<String> createAppToken({required String name});
}

/// The bundled engine could not do what was asked.
class LocalEngineException implements Exception {
  /// Creates the exception.
  const new(this.message);

  /// What went wrong, as the engine said it.
  final String message;

  @override
  String toString() => 'LocalEngineException: $message';
}

/// The [LocalEngine] at [executable] (`AppBundle.xpdExecutable`).
class BundledLocalEngine implements LocalEngine {
  /// Creates the engine.
  const new({required this.executable, this._run = Process.run});

  /// The engine executable.
  final String executable;

  final RunProcess _run;

  static final _token = RegExp(r'^xpt_[A-Za-z0-9_-]+$');

  @override
  bool get isBundled => File(executable).existsSync();

  @override
  Future<String> createAppToken({required String name}) async {
    if (!isBundled) {
      throw LocalEngineException('There is no engine at $executable.');
    }
    final ProcessResult result;
    try {
      result = await _run(executable, [
        'token',
        'create',
        '--name',
        name,
        '--kind',
        'app',
      ]);
    } on ProcessException catch (error) {
      throw LocalEngineException(error.message);
    }
    final token = (result.stdout as String).trim();
    if (result.exitCode != 0 || !_token.hasMatch(token)) {
      final error = (result.stderr as String).trim();
      throw LocalEngineException(
        error.isEmpty ? 'xpd token create exited ${result.exitCode}.' : error,
      );
    }
    return token;
  }
}
