import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/process/fan_out.dart';
import 'package:xp_engine/src/process/output_line.dart';
import 'package:xp_engine/src/process/output_masker.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';

/// Decides what a faked process does: write lines with
/// [FakeSupervisedProcess.emit] and return the exit code.
///
/// A handler that never returns makes a process that runs until it is
/// cancelled.
typedef FakeSupervisedHandler = FutureOr<int> Function(
  FakeSupervisedProcess process,
);

/// A [ProcessSupervisor] that starts no processes, for tests.
class FakeProcessSupervisor implements ProcessSupervisor {
  /// Creates a supervisor whose processes behave as [handler] says.
  new(this.handler, {required this._clock, this.masker = const NoMasking()});

  /// Decides what each process does.
  FakeSupervisedHandler handler;

  @override
  final OutputMasker masker;

  /// If set, [start] throws it.
  Exception? startError;

  /// If set, [start] waits for it.
  Future<void>? startGate;

  /// Every spec started so far, oldest first.
  final specs = <ProcessSpec>[];

  /// Every process started so far, oldest first.
  final processes = <FakeSupervisedProcess>[];

  final Clock _clock;
  var _nextPid = 4000;

  @override
  Future<SupervisedProcess> start(ProcessSpec spec) async {
    await startGate;
    final error = startError;
    if (error != null) throw error;
    specs.add(spec);
    final process = FakeSupervisedProcess._(
      spec,
      _nextPid++,
      _clock,
      () => handler,
    );
    processes.add(process);
    return process;
  }
}

/// A process faked by a [FakeProcessSupervisor].
class FakeSupervisedProcess implements SupervisedProcess {
  new _(this.spec, this.pid, this._clock, this._handler);

  /// What it was started with.
  final ProcessSpec spec;

  @override
  final int pid;

  final Clock _clock;
  final FakeSupervisedHandler Function() _handler;
  final _cancel = Completer<void>();
  final _finished = Completer<void>();
  var _seq = 0;
  var _running = false;

  @override
  final FanOut<OutputLine> output = FanOut(seqOf: (line) => line.seq);

  /// Completes when [cancel] was called.
  Future<void> get cancelRequested => _cancel.future;

  /// Whether [cancel] was called.
  bool get wasCancelled => _cancel.isCompleted;

  /// Writes [text] as a line of [stream], waiting for lossless subscribers.
  Future<void> emit(String text, {LogStream stream = LogStream.stdout}) =>
      output.add(
        OutputLine(
          seq: ++_seq,
          timestamp: _clock.now(),
          stream: stream,
          text: text,
        ),
      );

  @override
  Future<ProcessExit> run() async {
    _running = true;
    final exit = Completer<int>();
    unawaited(
      Future.sync(() => _handler()(this)).then((code) {
        if (!exit.isCompleted) exit.complete(code);
      }, onError: exit.completeError),
    );
    unawaited(
      cancelRequested.then((_) {
        if (!exit.isCompleted) exit.complete(-15);
      }),
    );
    try {
      final code = await exit.future;
      await output.close();
      return ProcessExit(exitCode: code, cancelled: wasCancelled);
    } finally {
      _finished.complete();
    }
  }

  @override
  Future<void> cancel() async {
    if (!_cancel.isCompleted) _cancel.complete();
    if (_running) await _finished.future;
  }
}

/// A [ProcessGroupControl] over groups that exist on paper, for tests.
class FakeProcessGroupControl implements ProcessGroupControl {
  /// Creates a control for the groups [alive], which die when signalled the
  /// way [dieOnTerminate] says.
  new({Iterable<int> alive = const [], this.dieOnTerminate = true})
    : alive = alive.toSet();

  /// The groups that are alive.
  final Set<int> alive;

  /// Whether `SIGTERM` ends a group. A group that ignores it needs `SIGKILL`.
  bool dieOnTerminate;

  /// The signals sent so far as `TERM <pgid>` and `KILL <pgid>`.
  final signals = <String>[];

  @override
  bool isAlive(int pgid) => alive.contains(pgid);

  @override
  void terminate(int pgid) {
    signals.add('TERM $pgid');
    if (dieOnTerminate) alive.remove(pgid);
  }

  @override
  void kill(int pgid) {
    signals.add('KILL $pgid');
    alive.remove(pgid);
  }
}
