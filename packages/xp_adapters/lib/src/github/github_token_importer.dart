import 'dart:async';

import 'package:xp_engine/xp_engine.dart';

/// `gh auth token` gave no usable token.
class GitHubTokenImportException implements Exception {
  /// Creates an exception with [message]. It never contains the token.
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'GitHubTokenImportException: $message';
}

/// Copies the token of the GitHub CLI into the secret store, so that the
/// engine can call GitHub and push without `gh` afterwards.
class GitHubTokenImporter {
  /// Creates an importer.
  ///
  /// [ghExecutable] is the GitHub CLI; the engine must be able to find it.
  const new({
    required this._runner,
    required this._secrets,
    this.ghExecutable = 'gh',
    this.timeout = const Duration(seconds: 30),
  });

  /// The program to run.
  final String ghExecutable;

  /// How long `gh` may take.
  final Duration timeout;

  final ProcessRunner _runner;
  final SecretStore _secrets;

  /// Runs `gh auth token` and stores the result under `github.token`.
  ///
  /// Throws a [GitHubTokenImportException] if `gh` is missing, not logged in
  /// or prints something that is not a token.
  Future<void> import() async {
    final ProcessOutput output;
    try {
      output = await _runner.run(
        ghExecutable,
        ['auth', 'token'],
        environment: {'GH_PROMPT_DISABLED': '1', 'NO_COLOR': '1'},
        timeout: timeout,
      );
    } on ProcessStartException catch (error) {
      throw GitHubTokenImportException('Cannot run gh: ${error.message}');
    } on TimeoutException {
      throw const GitHubTokenImportException('gh auth token timed out.');
    }
    final token = output.stdout.trim();
    if (output.exitCode != 0) {
      throw GitHubTokenImportException(
        'gh auth token failed (exit ${output.exitCode}): '
        '${output.stderr.trim()}',
      );
    }
    if (token.isEmpty || token.contains(RegExp(r'\s'))) {
      throw const GitHubTokenImportException(
        'gh auth token did not print a token.',
      );
    }
    await _secrets.write(githubTokenSecretKey, token);
  }
}
