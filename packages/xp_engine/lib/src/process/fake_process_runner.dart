import 'dart:async';

import 'package:xp_engine/src/process/process_runner.dart';

/// One process started on a [FakeProcessRunner].
class FakeProcessCall {
  /// Creates a record of a started process.
  new(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.environment,
  });

  /// The program that was started.
  final String executable;

  /// The arguments it was started with.
  final List<String> arguments;

  /// The directory it was started in, or `null` for the engine's.
  final String? workingDirectory;

  /// The environment added to the engine's for it, or `null`.
  final Map<String, String>? environment;

  /// Everything written to its standard input.
  String get stdin => _stdin.toString();
  final _stdin = StringBuffer();

  /// Whether the process was killed.
  bool killed = false;
}

/// Decides what a faked process outputs, once its standard input is closed.
typedef FakeProcessHandler = FutureOr<ProcessOutput> Function(
  FakeProcessCall call,
);

/// A [ProcessRunner] that starts no processes, for tests.
///
/// Each started process runs [handler] when its standard input is closed, and
/// its [RunningProcess.result] is what the handler returns. A handler that
/// never completes makes a process that hangs until it is killed.
class FakeProcessRunner implements ProcessRunner {
  /// Creates a runner whose processes answer with [handler].
  new(this.handler);

  /// Computes the output of each process.
  FakeProcessHandler handler;

  /// If set, [start] throws it.
  ProcessStartException? startError;

  /// Every process started so far, oldest first.
  final calls = <FakeProcessCall>[];

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final error = startError;
    if (error != null) throw error;
    final call = FakeProcessCall(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    calls.add(call);
    return _FakeRunningProcess(call, handler);
  }
}

class _FakeRunningProcess implements RunningProcess {
  new(this._call, this._handler);

  final FakeProcessCall _call;
  final FakeProcessHandler _handler;
  final _result = Completer<ProcessOutput>();

  @override
  Future<ProcessOutput> get result => _result.future;

  @override
  Future<void> writeStdin(String text) async => _call._stdin.write(text);

  @override
  Future<void> closeStdin() async {
    if (_result.isCompleted) return;
    unawaited(
      Future.sync(() => _handler(_call)).then(_complete, onError: _fail),
    );
  }

  @override
  void kill() {
    _call.killed = true;
    _complete(const ProcessOutput(exitCode: -15));
  }

  void _complete(ProcessOutput output) {
    if (!_result.isCompleted) _result.complete(output);
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (!_result.isCompleted) _result.completeError(error, stackTrace);
  }
}
