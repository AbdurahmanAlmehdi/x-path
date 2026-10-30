import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// What a faked command printed and how it ended.
class FakeRun {
  /// Creates the outcome.
  const new({this.exitCode = 0, this.lines = const [], this.cancelled = false});

  /// The exit code.
  final int exitCode;

  /// The lines it printed, on standard output unless they start with `err:`.
  final List<String> lines;

  /// Whether the step was cancelled.
  final bool cancelled;
}

/// A [StepContext] that runs no process: [handler] says what each command
/// printed, and the commands are kept for the test.
class ScriptedContext implements StepContext {
  /// Creates a context answering with [handler].
  new(this.handler);

  /// Decides the outcome of each command.
  FakeRun Function(ProcessCommand command) handler;

  /// Every command started, in order.
  final commands = <ProcessCommand>[];

  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<String> readDartDefines(String secretKey) =>
      throw StateError('This step reads no define file.');

  @override
  Future<String> writeSecretFile(String name, String contents) =>
      throw StateError('This step writes no secret file.');

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) async {
    commands.add(command);
    final outcome = handler(command);
    var seq = 0;
    for (final line in outcome.lines) {
      final error = line.startsWith('err:');
      onLine?.call(
        OutputLine(
          seq: ++seq,
          timestamp: DateTime.utc(2026),
          stream: error ? LogStream.stderr : LogStream.stdout,
          text: error ? line.substring(4) : line,
        ),
      );
    }
    return ProcessExit(
      exitCode: outcome.exitCode,
      cancelled: outcome.cancelled,
    );
  }
}

/// A [StepContext] that really runs the commands, with the environment the
/// command declares on top of the real one.
class ProcessContext implements StepContext {
  /// Every command started, in order.
  final commands = <ProcessCommand>[];

  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<String> readDartDefines(String secretKey) =>
      throw StateError('This step reads no define file.');

  @override
  Future<String> writeSecretFile(String name, String contents) =>
      throw StateError('This step writes no secret file.');

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) async {
    commands.add(command);
    final result = await Process.run(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: command.environment,
    );
    var seq = 0;
    for (final (stream, text) in [
      (LogStream.stdout, result.stdout as String),
      (LogStream.stderr, result.stderr as String),
    ]) {
      for (final line in const LineSplitter().convert(text)) {
        onLine?.call(
          OutputLine(
            seq: ++seq,
            timestamp: DateTime.now(),
            stream: stream,
            text: line,
          ),
        );
      }
    }
    return ProcessExit(exitCode: result.exitCode);
  }
}

/// A step that does what the test says.
class ScriptStep extends Step<Map<String, dynamic>, Map<String, dynamic>> {
  /// Creates a step of [kind].
  new(this.kind, this.onRun);

  @override
  final String kind;

  /// What [run] does.
  final Future<StepOutcome<Map<String, dynamic>>> Function(
    Map<String, dynamic> input,
    StepContext context,
  )
  onRun;

  @override
  bool sideEffectOf(Map<String, dynamic> input) => input['sideEffect'] == true;

  @override
  Map<String, dynamic> decodeInput(Map<String, dynamic> json) => json;

  @override
  Map<String, dynamic> encodeInput(Map<String, dynamic> input) => input;

  @override
  Map<String, dynamic> encodeResult(Map<String, dynamic> result) => result;

  @override
  Future<StepOutcome<Map<String, dynamic>>> run(
    Map<String, dynamic> input,
    StepContext context,
  ) => onRun(input, context);
}
