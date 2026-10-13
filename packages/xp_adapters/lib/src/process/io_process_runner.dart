import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_engine/xp_engine.dart';

/// A [ProcessRunner] over `dart:io`.
///
/// Arguments are passed as they are, never through a shell.
class IoProcessRunner implements ProcessRunner {
  /// Creates the runner.
  const new();

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return _IoRunningProcess(await Process.start(executable, arguments));
    } on ProcessException catch (error) {
      throw ProcessStartException(executable, error.message);
    }
  }
}

class _IoRunningProcess implements RunningProcess {
  new(this._process) : result = _collect(_process) {
    // A process that exits before it reads its input breaks the pipe. That is
    // not an error here: `result` carries its exit code.
    unawaited(_process.stdin.done.then<void>((_) {}, onError: (_) {}));
  }

  final Process _process;

  @override
  final Future<ProcessOutput> result;

  static Future<ProcessOutput> _collect(Process process) async {
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdout = decoder.bind(process.stdout).join();
    final stderr = decoder.bind(process.stderr).join();
    return ProcessOutput(
      exitCode: await process.exitCode,
      stdout: await stdout,
      stderr: await stderr,
    );
  }

  @override
  Future<void> writeStdin(String text) async {
    try {
      _process.stdin.write(text);
      await _process.stdin.flush();
    } on Object {
      // The process is gone; see the constructor.
    }
  }

  @override
  Future<void> closeStdin() async {
    try {
      await _process.stdin.close();
    } on Object {
      // The process is gone; see the constructor.
    }
  }

  @override
  void kill() {
    _process.kill();
  }
}
