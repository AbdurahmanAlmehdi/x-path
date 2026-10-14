import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// How much of the output of a probe command is kept: 64 KiB, as the protocol
/// says.
const int _outputLimit = 64 * 1024;

/// Runs the probe commands the engine sends (D-19).
///
/// The engine does not trust what a runner says about itself; it sends fixed
/// commands that only ask for versions or look for folders, and derives the
/// capabilities from what they print. A runner runs exactly these, in order,
/// and answers with one result each: `requires` (an earlier command must have
/// exited with 0) and `onlyOn` (`macos` or `linux`) can skip a command, a
/// program that is not installed is `not_started`, one that takes too long is
/// stopped and `timed_out`.
class ProbeExecutor {
  /// Creates the executor for a machine running `operatingSystem` (`macos` or
  /// `linux`).
  const new({required this._runner, required this._operatingSystem});

  final ProcessRunner _runner;
  final String _operatingSystem;

  /// Runs [commands] and returns their results, in order.
  Future<List<ProbeResult>> run(List<ProbeCommand> commands) async {
    final results = <ProbeResult>[];
    for (final command in commands) {
      results.add(await _run(command, results));
    }
    return results;
  }

  Future<ProbeResult> _run(
    ProbeCommand command,
    List<ProbeResult> before,
  ) async {
    final onlyOn = command.onlyOn;
    if (onlyOn != null && onlyOn != _operatingSystem) {
      return ProbeResult(id: command.id, status: ProbeStatus.skipped);
    }
    final requires = command.requires;
    if (requires != null &&
        !before.any((result) => result.id == requires && result.succeeded)) {
      return ProbeResult(id: command.id, status: ProbeStatus.skipped);
    }
    try {
      final output = await _runner.run(
        command.executable,
        command.arguments,
        timeout: Duration(seconds: command.timeoutSeconds),
      );
      return ProbeResult(
        id: command.id,
        status: ProbeStatus.exited,
        exitCode: output.exitCode,
        stdout: _cut(output.stdout),
        stderr: _cut(output.stderr),
      );
    } on ProcessStartException {
      return ProbeResult(id: command.id, status: ProbeStatus.notStarted);
    } on TimeoutException {
      return ProbeResult(id: command.id, status: ProbeStatus.timedOut);
    }
  }

  static String _cut(String text) =>
      text.length <= _outputLimit ? text : text.substring(0, _outputLimit);
}
