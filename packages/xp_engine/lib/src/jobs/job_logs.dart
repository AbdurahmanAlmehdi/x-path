import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/process/fan_out.dart';
import 'package:xp_engine/src/process/output_line.dart';

/// Appends the lines of one step to its log file.
abstract interface class JobLogWriter {
  /// Where the log is.
  String get path;

  /// Appends [line]. It can be read back when this completes.
  Future<void> write(LogLineFrame line);

  /// Closes the log.
  Future<void> close();
}

/// Where the log lines of jobs are kept: one log per step, under the data
/// directory (`logs/<jobId>/<ordinal>-<kind>.log`).
///
/// `xp_adapters` has the file implementation.
abstract interface class JobLogStore {
  /// Opens the log of a step for appending, creating it if needed.
  Future<JobLogWriter> open({
    required String jobId,
    required int ordinal,
    required String kind,
  });

  /// The lines of the job with a `seq` greater than [after], in order, across
  /// its steps.
  Stream<LogLineFrame> read(String jobId, {int after = 0});

  /// The `seq` of the newest line of the job, or 0 if it has none.
  Future<int> head(String jobId);
}

/// The log of a step that is running.
class StepLog {
  new _(this._session, this._writer, this.ordinal);

  final _JobSession _session;
  final JobLogWriter _writer;

  /// The step's position in the job.
  final int ordinal;

  /// Where the log file is.
  String get path => _writer.path;

  /// Numbers [line] in the log of the whole job, appends it to the file and
  /// shows it to the live readers, in that order.
  Future<void> record(OutputLine line) async {
    final frame = LogLineFrame(
      seq: ++_session.seq,
      step: ordinal,
      at: line.timestamp,
      stream: line.stream,
      text: line.text,
    );
    await _writer.write(frame);
    await _session.live.add(frame);
  }

  /// Closes the file.
  Future<void> close() => _writer.close();
}

class _JobSession {
  new(this.seq) : live = FanOut(seqOf: (line) => line.seq);

  int seq;
  final FanOut<LogLineFrame> live;
}

/// The logs of jobs: stored per step, numbered across the job, replayable by
/// sequence number and followable live.
///
/// While a job runs ([begin] to [end]) its lines are also shown to live
/// readers. A live reader that falls behind loses its oldest queued lines and
/// is told so with a [FanOutGap]; the log file always has every line (D-24
/// keeps logs for 90 days; pruning is a housekeeping concern).
class JobLogs {
  /// Creates the logs over [_store]. Live readers queue at most
  /// [liveCapacity] lines.
  new({required this._store, this.liveCapacity = 1024});

  /// How many lines a live reader may be behind before it loses some.
  final int liveCapacity;

  final JobLogStore _store;
  final _sessions = <String, _JobSession>{};

  /// Whether the job [jobId] is between [begin] and [end].
  bool isActive(String jobId) => _sessions.containsKey(jobId);

  /// Starts the log of a job that runs now. Its numbering continues after the
  /// lines it logged before, so a resumed job keeps counting.
  Future<void> begin(String jobId) async {
    _sessions[jobId] = _JobSession(await _store.head(jobId));
  }

  /// Opens the log of step [ordinal] of the running job [jobId].
  ///
  /// Throws a [StateError] if the job did not [begin].
  Future<StepLog> openStep(String jobId, int ordinal, String kind) async {
    final session = _sessions[jobId];
    if (session == null) throw StateError('Job $jobId has not begun.');
    return StepLog._(
      session,
      await _store.open(jobId: jobId, ordinal: ordinal, kind: kind),
      ordinal,
    );
  }

  /// Ends the log of the job: live readers receive what is queued, then end.
  Future<void> end(String jobId) async {
    final session = _sessions.remove(jobId);
    if (session != null) await session.live.close();
  }

  /// The `seq` of the newest line of the job.
  Future<int> head(String jobId) async =>
      _sessions[jobId]?.seq ?? await _store.head(jobId);

  /// The lines of the job after [after], then, if the job is running, the
  /// lines it logs from now on until it ends.
  ///
  /// No line is missed or repeated, whatever the timing of the replay and the
  /// live lines.
  ///
  /// Cancelling the stream takes effect when the next line arrives or the job
  /// ends, whichever comes first.
  Stream<FanOutEvent<LogLineFrame>> follow(
    String jobId, {
    int after = 0,
  }) async* {
    final live = _sessions[jobId]?.live.watch(capacity: liveCapacity);
    var listening = false;
    try {
      var last = after;
      await for (final line in _store.read(jobId, after: after)) {
        yield FanOutItem(line);
        last = line.seq;
      }
      if (live == null) return;
      listening = true;
      await for (final event in live) {
        switch (event) {
          case FanOutItem(:final value) when value.seq <= last:
            break;
          case FanOutItem(:final value):
            yield event;
            last = value.seq;
          case FanOutGap(:final fromSeq, :final toSeq, :final count):
            if (toSeq > last) {
              // Part of the gap may have been replayed already.
              final from = fromSeq > last ? fromSeq : last + 1;
              yield FanOutGap<LogLineFrame>(
                fromSeq: from,
                toSeq: toSeq,
                count: count - (from - fromSeq),
              );
              last = toSeq;
            }
        }
      }
    } finally {
      // A reader that was never listened to would stay subscribed.
      if (live != null && !listening) await live.listen(null).cancel();
    }
  }
}

/// A [JobLogStore] in memory, for tests.
class InMemoryJobLogStore implements JobLogStore {
  /// The lines by job, in the order they were written.
  final lines = <String, List<LogLineFrame>>{};

  /// The paths of the logs that were opened.
  final paths = <String>[];

  @override
  Future<JobLogWriter> open({
    required String jobId,
    required int ordinal,
    required String kind,
  }) async {
    final path = '/logs/$jobId/$ordinal-$kind.log';
    paths.add(path);
    return _Writer(path, lines.putIfAbsent(jobId, () => []));
  }

  @override
  Stream<LogLineFrame> read(String jobId, {int after = 0}) =>
      Stream.fromIterable([
        for (final line in lines[jobId] ?? const <LogLineFrame>[])
          if (line.seq > after) line,
      ]);

  @override
  Future<int> head(String jobId) async => lines[jobId]?.lastOrNull?.seq ?? 0;
}

class _Writer implements JobLogWriter {
  new(this.path, this._lines);

  @override
  final String path;
  final List<LogLineFrame> _lines;

  @override
  Future<void> write(LogLineFrame line) async => _lines.add(line);

  @override
  Future<void> close() async {}
}
