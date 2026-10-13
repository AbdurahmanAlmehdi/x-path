import 'dart:io';

import 'package:xp_engine/xp_engine.dart';

/// Signals process groups with `kill(2)` and a negated group id (ADR 0003).
class IoProcessGroupControl implements ProcessGroupControl {
  /// Creates the control.
  const new();

  @override
  bool isAlive(int pgid) {
    // Signal 0 sends nothing; it only says whether the group exists. The
    // `kill` builtin of `sh` exists on every machine, `/bin/kill` does not.
    // `-s 0 --` is the one spelling that macOS (bash) and Debian (dash) both
    // accept for a negative id.
    final result = Process.runSync('/bin/sh', [
      '-c',
      r'kill -s 0 -- "$1"',
      'sh',
      '-$pgid',
    ]);
    return result.exitCode == 0;
  }

  @override
  void terminate(int pgid) => Process.killPid(-pgid);

  @override
  void kill(int pgid) => Process.killPid(-pgid, ProcessSignal.sigkill);
}
