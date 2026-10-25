import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// What a faked command does: the lines it prints and how it ends.
typedef CommandBehavior = ({
  List<String> stdout,
  List<String> stderr,
  ProcessExit exit,
});

/// A [StepContext] that hands the lines each command prints to its `onLine`,
/// the way the job runner does, and ends it as the test says.
class StreamingContext implements StepContext {
  /// Creates a context for the job [jobId] whose commands behave as [behave]
  /// says, given the command and how many commands ran before it.
  new(this.behave, {this.jobId = 'job_1'});

  /// A context where every command prints [stdout] and exits with [exit].
  factory single(
    List<String> stdout, {
    List<String> stderr = const [],
    ProcessExit exit = const ProcessExit(exitCode: 0),
    String jobId = 'job_1',
  }) => StreamingContext(
    (command, index) => (stdout: stdout, stderr: stderr, exit: exit),
    jobId: jobId,
  );

  /// Decides what a command does.
  final CommandBehavior Function(ProcessCommand command, int index) behave;

  @override
  final String jobId;

  /// The commands that ran, in order.
  final commands = <ProcessCommand>[];

  @override
  int get ordinal => 0;

  /// Whether the job is stopping; a test sets it.
  @override
  bool isStopping = false;

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) async {
    final behavior = behave(command, commands.length);
    commands.add(command);
    var seq = 0;
    void emit(LogStream stream, List<String> lines) {
      for (final text in lines) {
        onLine?.call(
          OutputLine(
            seq: ++seq,
            timestamp: DateTime.utc(2026),
            stream: stream,
            text: text,
          ),
        );
      }
    }

    emit(LogStream.stdout, behavior.stdout);
    emit(LogStream.stderr, behavior.stderr);
    return behavior.exit;
  }
}

/// A random source that is always 0, so that ids are predictable.
class ZeroRandom implements Random {
  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();

  @override
  int nextInt(int max) => 0;
}
