import 'dart:async';

import 'package:xp_api/xp_api.dart';

/// What a lease has to say to the engine, and keeps until the engine has it.
///
/// A runner talks to the engine over a connection that can drop. Everything a
/// job reports is therefore kept until it is acknowledged, and sent again
/// after a reconnect, so that the engine ends up with the whole log, every
/// step state and the end of the job (D-08):
///
/// - **Log lines** are cut into chunks of at most [maxLines] lines, numbered
///   from 1 per lease. A chunk stays until a `chunk_ack` says the engine has
///   it. A `gap` ack says where the engine wants to go on, and the chunks from
///   there are sent again.
/// - **Step states** are idempotent; the newest of each step stays until the
///   job is done.
/// - **The end** (`job_done`) stays until the `done_ack`. It carries the
///   number of the last chunk, which the engine checks before it ends the job.
class LeaseOutbox {
  /// Creates the outbox of the lease `leaseId` of `jobId`. `send` hands a frame
  /// to the connection and silently drops it when there is none.
  new({
    required this.jobId,
    required this.leaseId,
    required this._send,
    this.maxLines = 500,
    this.flushDelay = const Duration(milliseconds: 250),
  });

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The most lines in one chunk. The protocol allows 5000.
  final int maxLines;

  /// How long lines wait for company before they are sent as a chunk.
  final Duration flushDelay;

  final void Function(RunnerFrame frame) _send;
  final _lines = <ChunkLine>[];
  final _chunks = <int, LogChunkFrame>{};
  final _steps = <int, StepStateFrame>{};
  final _acknowledged = Completer<void>();
  JobDoneFrame? _done;
  Timer? _timer;
  var _lastChunk = 0;

  /// The number of the last chunk made, 0 if none.
  int get lastChunk => _lastChunk;

  /// Completes when the engine acknowledged the end of the job.
  Future<void> get acknowledged => _acknowledged.future;

  /// Whether the engine acknowledged the end of the job.
  bool get isAcknowledged => _acknowledged.isCompleted;

  /// Whether the job ended and the engine has not acknowledged it yet.
  bool get awaitsAcknowledgement => _done != null && !isAcknowledged;

  /// Adds a line of the log.
  void line(ChunkLine line) {
    _lines.add(line);
    if (_lines.length >= maxLines) {
      flush();
    } else {
      _timer ??= Timer(flushDelay, flush);
    }
  }

  /// Sends the lines that wait as a chunk.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_lines.isEmpty) return;
    final chunk = LogChunkFrame(
      jobId: jobId,
      leaseId: leaseId,
      seq: ++_lastChunk,
      lines: List.of(_lines),
    );
    _lines.clear();
    _chunks[chunk.seq] = chunk;
    _send(chunk);
  }

  /// Reports where a step is.
  void step(StepStateFrame frame) {
    _steps[frame.ordinal] = frame;
    _send(frame);
  }

  /// Ends the job: sends the lines that wait, then `job_done`.
  void finish({required JobState state, String? message}) {
    flush();
    final done = JobDoneFrame(
      jobId: jobId,
      leaseId: leaseId,
      state: state,
      lastChunk: _lastChunk,
      message: message,
    );
    _done = done;
    _send(done);
  }

  /// The engine answered a chunk.
  void chunkAcknowledged(ChunkAckFrame ack) {
    _chunks.removeWhere((seq, _) => seq < ack.next);
    if (ack.status != ChunkStatus.gap) return;
    // The engine wants to go on at `next`: what it lacks, and then the end of
    // the job again, which it refused to take while the log had a hole.
    _sendChunks();
    final done = _done;
    if (done != null) _send(done);
  }

  /// The engine recorded the end of the job.
  void doneAcknowledged() {
    _chunks.clear();
    _steps.clear();
    _done = null;
    if (!_acknowledged.isCompleted) _acknowledged.complete();
  }

  /// Sends everything the engine may not have again, after a reconnect.
  void resend() {
    _sendChunks();
    for (final ordinal in _steps.keys.toList()..sort()) {
      _send(_steps[ordinal]!);
    }
    final done = _done;
    if (done != null) _send(done);
  }

  /// Drops what waits: the lease is over and nothing more is reported.
  void abandon() {
    _timer?.cancel();
    _timer = null;
    _lines.clear();
    _chunks.clear();
    _steps.clear();
    _done = null;
  }

  void _sendChunks() {
    for (final seq in _chunks.keys.toList()..sort()) {
      _send(_chunks[seq]!);
    }
  }
}
