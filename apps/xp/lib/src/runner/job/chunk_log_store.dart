import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The log of a leased job: every line goes to the [LeaseOutbox], which sends
/// it to the engine in numbered chunks. A runner keeps no log file; the
/// engine's log of the job is the one.
class ChunkLogStore implements JobLogStore {
  /// Creates the store over [_outbox].
  const new(this._outbox);

  final LeaseOutbox _outbox;

  @override
  Future<JobLogWriter> open({
    required String jobId,
    required int ordinal,
    required String kind,
  }) async => _Writer('lease/$jobId/$ordinal-$kind', _outbox);

  @override
  Stream<LogLineFrame> read(String jobId, {int after = 0}) =>
      const Stream.empty();

  @override
  Future<int> head(String jobId) async => 0;
}

class _Writer implements JobLogWriter {
  const new(this.path, this._outbox);

  @override
  final String path;
  final LeaseOutbox _outbox;

  @override
  Future<void> write(LogLineFrame line) async => _outbox.line(
    ChunkLine(
      step: line.step,
      at: line.at,
      stream: line.stream,
      text: line.text,
    ),
  );

  @override
  Future<void> close() async {}
}
