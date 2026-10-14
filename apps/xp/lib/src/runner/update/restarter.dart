import 'dart:async';
import 'dart:io';

import 'package:xp/src/exit_codes.dart';

/// The variable the LaunchAgent and the systemd unit of a runner set to `1`:
/// a service manager restarts the runner, so the runner only has to exit.
const runnerManagedVariable = 'XP_RUNNER_MANAGED';

/// Starts [executable] with [arguments] in place of this process, with the
/// same standard streams, and returns its exit code.
typedef ProcessLauncher = Future<int> Function(
  String executable,
  List<String> arguments,
);

/// Starts the runner again as the version it switched to (D-24).
///
/// - **Under a service manager** (`XP_RUNNER_MANAGED=1`, set by the service
///   `xp runner install-service` writes): the runner exits with
///   [XpExit.restart]. The manager starts `current/bin/xp` again because the
///   exit is a failure (`KeepAlive` with `SuccessfulExit` false, `Restart=on-
///   failure`), and `current` is the new version.
/// - **Otherwise** (a runner started by hand): this process starts
///   `current/bin/xp runner start ...` with the same terminal, waits for it
///   and exits with its code. Dart cannot replace a process, so the old
///   process stays as the parent until the runner ends; it holds nothing.
class Restarter {
  /// Creates the restarter. [managed] says whether a service manager restarts
  /// the runner. [launch] is for tests.
  const new({required this.managed, this.launch = launchInheriting});

  /// Whether a service manager restarts the runner.
  final bool managed;

  /// Starts the program in place of this process.
  final ProcessLauncher launch;

  /// Starts [executable] with [arguments] as the new runner, or exits for the
  /// manager to do so. Returns the exit code of this process.
  Future<int> restart(
    String executable,
    List<String> arguments,
    void Function(String message) log,
  ) {
    if (managed) {
      log('Exiting to let the service manager start the new version.');
      return Future.value(XpExit.restart);
    }
    log('Starting the new version: $executable ${arguments.join(' ')}');
    return launch(executable, arguments);
  }
}

/// Runs [executable] with the streams of this process and returns its exit
/// code. A stop signal sent to this process goes on to the program.
Future<int> launchInheriting(String executable, List<String> arguments) async {
  final child = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final forwarded = [
    for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint])
      signal.watch().listen(child.kill),
  ];
  try {
    return await child.exitCode;
  } finally {
    for (final subscription in forwarded) {
      await subscription.cancel();
    }
  }
}
