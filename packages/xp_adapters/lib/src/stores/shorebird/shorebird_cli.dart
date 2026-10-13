import 'dart:async';
import 'dart:convert';

import 'package:xp_engine/xp_engine.dart';

/// How a run of the Shorebird CLI ended.
sealed class ShorebirdCliResult {
  const new();
}

/// The CLI exited 0 and printed the documented JSON envelope with
/// `"status": "success"`.
final class ShorebirdCliSuccess extends ShorebirdCliResult {
  /// Creates the result.
  const new(this.data);

  /// The `data` member of the envelope; empty if it had none.
  final Map<String, dynamic> data;
}

/// Why the CLI did not give a result.
enum ShorebirdCliProblem {
  /// The program could not be started: Shorebird is not installed.
  missing,

  /// It did not answer in time.
  timedOut,

  /// It exited non-zero, or exited 0 and did not print the JSON envelope.
  failed,
}

/// The CLI gave no result.
final class ShorebirdCliFailure extends ShorebirdCliResult {
  /// Creates the failure.
  const new(this.problem, this.output);

  /// What went wrong.
  final ShorebirdCliProblem problem;

  /// Everything the CLI printed, standard output first. It can carry the
  /// token if the CLI echoes it; callers must not show it unmasked.
  final String output;
}

/// The Shorebird CLI, always run without prompts and with `--json`.
///
/// Phase 9c's release listing and Phase 10c's credential check both go through
/// it, so the way the CLI is run is in one place: `CI=true` keeps it from
/// prompting, and an API key (`sb_api_*`, D-20) reaches it in
/// `SHOREBIRD_TOKEN`, never in the arguments. Without a token the CLI uses
/// whatever login the machine has.
class ShorebirdCli {
  /// Creates the wrapper. The CLI is [executable]; it has [timeout] to answer.
  const new({
    required this._runner,
    this.executable = 'shorebird',
    this.timeout = const Duration(minutes: 2),
  });

  /// The Shorebird CLI.
  final String executable;

  /// How long the CLI has to answer.
  final Duration timeout;

  final ProcessRunner _runner;

  /// Runs the CLI with [arguments] (they must ask for JSON) and reads the
  /// envelope `{"status": "success", "data": {...}}`.
  Future<ShorebirdCliResult> run(
    List<String> arguments, {
    String? token,
  }) async {
    final ProcessOutput output;
    try {
      output = await _runner.run(
        executable,
        arguments,
        environment: {'CI': 'true', 'SHOREBIRD_TOKEN': ?token},
        timeout: timeout,
      );
    } on ProcessStartException {
      return const ShorebirdCliFailure(ShorebirdCliProblem.missing, '');
    } on TimeoutException {
      return const ShorebirdCliFailure(ShorebirdCliProblem.timedOut, '');
    }
    final text = '${output.stdout}\n${output.stderr}'.trim();
    if (output.exitCode != 0) {
      return ShorebirdCliFailure(ShorebirdCliProblem.failed, text);
    }
    final Object? json;
    try {
      json = jsonDecode(output.stdout);
    } on FormatException {
      return ShorebirdCliFailure(ShorebirdCliProblem.failed, text);
    }
    if (json is! Map<String, dynamic> || json['status'] != 'success') {
      return ShorebirdCliFailure(ShorebirdCliProblem.failed, text);
    }
    final data = json['data'];
    return ShorebirdCliSuccess(data is Map<String, dynamic> ? data : const {});
  }
}
