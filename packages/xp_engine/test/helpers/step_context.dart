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
  Future<String> readDartDefines(String secretKey) =>
      throw StateError('This step reads no define file.');

  @override
  Future<String> writeSecretFile(String name, String contents) =>
      throw StateError('This step writes no secret file.');

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) => throw StateError('This step must not start a process.');
}
