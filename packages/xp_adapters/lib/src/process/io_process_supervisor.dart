import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_adapters/src/process/executable_lookup.dart';
import 'package:xp_adapters/src/process/io_process_group_control.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The Perl program that makes the process a process-group leader and then
/// becomes the real command (ADR 0003). The block form of `exec` never uses a
/// shell, whatever the arguments hold.
const processGroupTrampoline =
    r'setpgrp(0,0); exec { $ARGV[0] } @ARGV or die "exec: $!"';

/// A [ProcessSupervisor] over `dart:io`.
///
/// Each process starts through a `perl` trampoline that makes it the leader
/// of a new process group, so that its process id is also its group id and
/// [SupervisedProcess.cancel] can stop the whole tree (ADR 0003). The
/// environment is exactly the one in the [ProcessSpec]: nothing is inherited.
///
/// Output is read as UTF-8 (invalid bytes become U+FFFD), masked per stream,
/// cut into lines and handed to [SupervisedProcess.output].
class IoProcessSupervisor implements ProcessSupervisor {
  /// Creates a supervisor.
  ///
  /// [path] is the `PATH` where `perl` is looked for (default: the engine's).
  /// [grace] is how long a cancelled group has to end before it is killed.
  /// [drainTimeout] is how long the output is still read after the process
  /// exited: a daemon it left behind may hold the pipes open for ever.
  new({
    required this.masker,
    required this._clock,
    String? path,
    ProcessGroupControl control = const IoProcessGroupControl(),
    Duration grace = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 50),
    this.drainTimeout = const Duration(seconds: 2),
  }) : _path = path ?? Platform.environment['PATH'],
       _killer = ProcessGroupKiller(
         control: control,
         grace: grace,
         pollInterval: pollInterval,
       );

  @override
  final OutputMasker masker;

  /// How long output is read after the process exited.
  final Duration drainTimeout;

  final Clock _clock;
  final String? _path;
  final ProcessGroupKiller _killer;

  /// The `perl` the trampoline runs on.
  ///
  /// Throws a [ToolchainException] if there is none: `perl` ships with macOS
  /// and with Debian and Ubuntu (`perl-base`), so a machine without it needs
  /// it installed.
  String requirePerl() =>
      findExecutable('perl', _path) ??
      (throw const ToolchainException(
        'perl',
        'perl was not found on PATH. XPath uses it to put every step in its '
            'own process group so that a cancel stops the whole tree. It ships '
            'with macOS and Debian/Ubuntu (package perl-base); install it and '
            'make sure it is on PATH.',
      ));

  @override
  Future<SupervisedProcess> start(ProcessSpec spec) async {
    final perl = requirePerl();
    final executable = findExecutable(
      spec.executable,
      spec.environment['PATH'],
    );
    if (executable == null) {
      throw ProcessStartException(
        spec.executable,
        'No such executable on PATH or at that path.',
      );
    }
    final Process process;
    try {
      process = await Process.start(
        perl,
        ['-e', processGroupTrampoline, '--', executable, ...spec.arguments],
        workingDirectory: spec.workingDirectory,
        environment: spec.environment,
        includeParentEnvironment: false,
      );
    } on ProcessException catch (error) {
      throw ProcessStartException(spec.executable, error.message);
    }
    // Nothing is ever written to a step process.
    unawaited(process.stdin.close().then<void>((_) {}, onError: (_) {}));
    return _IoSupervisedProcess(process, this);
  }
}

class _IoSupervisedProcess implements SupervisedProcess {
  new(this._process, this._supervisor);

  final Process _process;
  final IoProcessSupervisor _supervisor;
  var _seq = 0;
  var _cancelled = false;
  Future<void>? _cancelling;

  @override
  int get pid => _process.pid;

  @override
  final FanOut<OutputLine> output = FanOut(seqOf: (line) => line.seq);

  @override
  Future<ProcessExit> run() async {
    final pumps = [
      _Pump(_process.stdout, LogStream.stdout, this),
      _Pump(_process.stderr, LogStream.stderr, this),
    ];
    final exitCode = await _process.exitCode;
    // The output is complete once both pipes are closed. A daemon the process
    // left behind can keep them open, so do not wait for ever.
    await Future.wait(pumps.map((pump) => pump.done))
        .timeout(_supervisor.drainTimeout, onTimeout: () => <void>[]);
    for (final pump in pumps) {
      await pump.stop();
    }
    await output.close();
    return ProcessExit(exitCode: exitCode, cancelled: _cancelled);
  }

  @override
  Future<void> cancel() => _cancelling ??= _cancel();

  Future<void> _cancel() async {
    _cancelled = true;
    var exited = false;
    unawaited(_process.exitCode.then((_) => exited = true));
    await _supervisor._killer.stop(pid);
    // The process may not have become a group leader yet, or the group may
    // be gone while the leader is not: make sure it ends.
    if (!exited) {
      _process.kill(ProcessSignal.sigkill);
    }
    await _process.exitCode;
  }

  Future<void> _emit(LogStream stream, Iterable<String> lines) async {
    for (final text in lines) {
      await output.add(
        OutputLine(
          seq: ++_seq,
          timestamp: _supervisor._clock.now(),
          stream: stream,
          text: text,
        ),
      );
    }
  }
}

/// Reads one pipe: decodes, masks and cuts it into lines.
class _Pump {
  new(Stream<List<int>> bytes, this._stream, this._owner) {
    final masking = _owner._supervisor.masker.newStream();
    final lines = LineAssembler();
    _subscription = const Utf8Decoder(allowMalformed: true)
        .bind(bytes)
        .listen(
          (text) async {
            // One piece at a time: reading goes on when the lines were taken.
            _subscription.pause();
            await _owner._emit(_stream, lines.add(masking.add(text)));
            _subscription.resume();
          },
          onDone: () async {
            final rest = lines.add(masking.flush());
            await _owner._emit(_stream, [...rest, ?lines.flush()]);
            _done.complete();
          },
        );
  }

  final LogStream _stream;
  final _IoSupervisedProcess _owner;
  final _done = Completer<void>();
  late final StreamSubscription<String> _subscription;

  Future<void> get done => _done.future;

  /// Stops reading, if the pipe is still open.
  Future<void> stop() => _subscription.cancel();
}
