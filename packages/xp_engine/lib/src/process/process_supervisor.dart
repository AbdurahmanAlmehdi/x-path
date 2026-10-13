import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/process/fan_out.dart';
import 'package:xp_engine/src/process/output_line.dart';
import 'package:xp_engine/src/process/output_masker.dart';

/// A tool the engine needs is not there (ADR 0003: `perl`; later phases:
/// `flutter`, `xcodebuild`, ...).
class ToolchainException implements Exception {
  /// Creates an exception for [tool].
  const new(this.tool, this.message);

  /// The tool that is missing or unusable.
  final String tool;

  /// What is wrong and how to fix it.
  final String message;

  @override
  String toString() => 'ToolchainException: $tool: $message';
}

/// What to run for a step.
class ProcessSpec extends Equatable {
  /// Creates a spec.
  const new(
    this.executable,
    this.arguments, {
    required this.environment,
    this.workingDirectory,
  });

  /// The program. Looked up in `PATH` of [environment].
  final String executable;

  /// Its arguments, never run through a shell.
  final List<String> arguments;

  /// The whole environment of the process: it inherits nothing else. See
  /// `allowlistedEnvironment`.
  final Map<String, String> environment;

  /// The directory it runs in, or `null` for the engine's.
  final String? workingDirectory;

  @override
  List<Object?> get props => [
    executable,
    arguments,
    environment,
    workingDirectory,
  ];
}

/// How a supervised process ended.
class ProcessExit extends Equatable {
  /// Creates the result of a process that ended with [exitCode].
  const new({required this.exitCode, this.cancelled = false});

  /// The exit code. A process killed by a signal has the negated signal
  /// number, for example -15 for `SIGTERM`.
  final int exitCode;

  /// Whether it ended because [SupervisedProcess.cancel] was called.
  final bool cancelled;

  /// Whether it exited with code 0.
  bool get succeeded => exitCode == 0 && !cancelled;

  @override
  List<Object?> get props => [exitCode, cancelled];
}

/// A process started by a [ProcessSupervisor].
abstract interface class SupervisedProcess {
  /// The process id, which is also the id of its process group (ADR 0003).
  int get pid;

  /// The lines the process writes, masked, with a sequence number and a time.
  ///
  /// Subscribe before calling [run]: a subscriber only sees the lines that
  /// follow. The fan-out ends when the process has exited and all its output
  /// was read.
  FanOut<OutputLine> get output;

  /// Starts reading the output and completes when the process has exited and
  /// every line was handed to the subscribers of [output].
  Future<ProcessExit> run();

  /// Stops the process and everything it started: `SIGTERM` to the process
  /// group, a grace period, then `SIGKILL` (ADR 0003). Completes when the
  /// process has ended.
  Future<void> cancel();
}

/// Starts step processes, each in its own process group.
///
/// `xp_adapters` has the `dart:io` implementation.
abstract interface class ProcessSupervisor {
  /// Masks every line the supervised processes write before it is handed to
  /// [SupervisedProcess.output]. Add a secret to it before passing the secret
  /// to a process.
  OutputMasker get masker;

  /// Starts [spec]. Its output is not read before [SupervisedProcess.run].
  ///
  /// Throws a `ProcessStartException` if it cannot be started and a
  /// [ToolchainException] if the machine lacks what supervising needs.
  Future<SupervisedProcess> start(ProcessSpec spec);
}

/// Signals process groups.
///
/// `xp_adapters` has the `dart:io` implementation, over `kill(2)` with the
/// negated group id (ADR 0003).
abstract interface class ProcessGroupControl {
  /// Whether any process of the group [pgid] is alive.
  bool isAlive(int pgid);

  /// Sends `SIGTERM` to the group.
  void terminate(int pgid);

  /// Sends `SIGKILL` to the group.
  void kill(int pgid);
}

/// Stops a process group the way ADR 0003 prescribes.
class ProcessGroupKiller {
  /// Creates a killer.
  ///
  /// [delay] is for tests; it defaults to [Future.delayed].
  new({
    required this._control,
    this.grace = const Duration(seconds: 10),
    this.pollInterval = const Duration(milliseconds: 50),
    Future<void> Function(Duration duration)? delay,
  }) : assert(pollInterval > Duration.zero, 'pollInterval must be positive'),
       _delay = delay ?? Future<void>.delayed;

  /// How long the group may take to end after `SIGTERM`.
  final Duration grace;

  /// How often the group is looked at during the grace period.
  final Duration pollInterval;

  final ProcessGroupControl _control;
  final Future<void> Function(Duration duration) _delay;

  /// Sends `SIGTERM` to the group [pgid], waits up to [grace] for every
  /// process in it to end, then sends `SIGKILL` to those that remain.
  ///
  /// Returns whether `SIGKILL` was needed. Never signals a group that is not
  /// alive, nor a group id that cannot be one (below 2).
  Future<bool> stop(int pgid) async {
    if (pgid < 2 || !_control.isAlive(pgid)) return false;
    _control.terminate(pgid);
    var waited = Duration.zero;
    while (waited < grace && _control.isAlive(pgid)) {
      await _delay(pollInterval);
      waited += pollInterval;
    }
    if (!_control.isAlive(pgid)) return false;
    _control.kill(pgid);
    return true;
  }
}
