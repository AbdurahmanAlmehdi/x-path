import 'package:xp_engine/xp_engine.dart';

/// A [StepContext] for steps that run no process.
class NoProcessContext implements StepContext {
  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) => throw StateError('This step must not start a process.');
}
