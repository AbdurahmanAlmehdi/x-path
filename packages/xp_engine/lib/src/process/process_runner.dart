import 'dart:async';

import 'package:equatable/equatable.dart';

/// What a finished child process produced.
class ProcessOutput extends Equatable {
  /// Creates the output of a process that exited with [exitCode].
  const new({required this.exitCode, this.stdout = '', this.stderr = ''});

  /// The exit code. Non-zero means failure.
  final int exitCode;

  /// Everything written to standard output.
  final String stdout;

  /// Everything written to standard error.
  final String stderr;

  @override
  List<Object?> get props => [exitCode, stdout, stderr];
}

/// Thrown by [ProcessRunner.start] when the program cannot be started, for
/// example because it does not exist.
class ProcessStartException implements Exception {
  /// Creates an exception for [executable].
  const new(this.executable, this.message);

  /// The program that could not be started.
  final String executable;

  /// Why it could not be started.
  final String message;

  @override
  String toString() => 'ProcessStartException: $executable: $message';
}

/// A child process that has been started.
abstract interface class RunningProcess {
  /// Writes [text] to the standard input of the process.
  ///
  /// Never throws if the process has already exited: its exit code in
  /// [result] says what happened.
  Future<void> writeStdin(String text);

  /// Closes the standard input of the process.
  Future<void> closeStdin();

  /// Asks the process to stop.
  void kill();

  /// Completes when the process has exited and all its output was read.
  Future<ProcessOutput> get result;
}

/// Starts child processes.
///
/// The engine runs every program through this interface, so that tests can
/// fake them. `xp_adapters` has the `dart:io` implementation. Arguments are
/// never run through a shell.
abstract interface class ProcessRunner {
  /// Starts [executable] with [arguments].
  ///
  /// Throws a [ProcessStartException] if it cannot be started.
  Future<RunningProcess> start(String executable, List<String> arguments);
}

/// Conveniences over [ProcessRunner.start].
extension ProcessRunnerRun on ProcessRunner {
  /// Runs [executable] to completion, feeding it [stdin] if given.
  ///
  /// If the process takes longer than [timeout] it is killed and a
  /// [TimeoutException] is thrown.
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    String? stdin,
    Duration? timeout,
  }) async {
    final process = await start(executable, arguments);
    if (stdin != null) await process.writeStdin(stdin);
    await process.closeStdin();
    if (timeout == null) return await process.result;
    try {
      return await process.result.timeout(timeout);
    } on TimeoutException {
      process.kill();
      rethrow;
    }
  }
}
