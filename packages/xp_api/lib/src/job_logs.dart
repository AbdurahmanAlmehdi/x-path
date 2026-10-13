import 'package:equatable/equatable.dart';
import 'package:xp_api/src/job.dart';

/// Which stream of a process a line of output came from.
enum LogStream {
  /// Standard output.
  stdout,

  /// Standard error.
  stderr,
}

/// One frame of the `GET /jobs/{id}/logs` WebSocket.
///
/// The wire form is a JSON object with a `type`: `line`, `gap` or `end`.
sealed class LogFrame extends Equatable {
  const new();

  /// Reads a frame from its JSON form.
  ///
  /// Throws a [FormatException] for a type this client does not know.
  factory fromJson(Map<String, dynamic> json) => switch (json['type']) {
    LogLineFrame.frameType => LogLineFrame(
      seq: json['seq'] as int,
      step: json['step'] as int,
      at: DateTime.parse(json['at'] as String),
      stream: LogStream.values.byName(json['stream'] as String),
      text: json['text'] as String,
    ),
    LogGapFrame.frameType => LogGapFrame(
      fromSeq: json['fromSeq'] as int,
      toSeq: json['toSeq'] as int,
      count: json['count'] as int,
    ),
    LogEndFrame.frameType => LogEndFrame(
      state: JobState.values.firstWhere((state) => state.wire == json['state']),
    ),
    final Object? other => throw FormatException('Unknown log frame: $other'),
  };

  /// The wire name of the frame.
  String get type;

  /// The JSON form.
  Map<String, dynamic> toJson();
}

/// One line of a process's output.
final class LogLineFrame extends LogFrame {
  /// Creates the frame.
  const new({
    required this.seq,
    required this.step,
    required this.at,
    required this.stream,
    required this.text,
  });

  /// The wire name of this frame.
  static const frameType = 'line';

  /// Position in the job's log, from 1. A client that handled `seq` 7
  /// resumes with `?after=7`.
  final int seq;

  /// The ordinal of the step that wrote the line.
  final int step;

  /// When the line was read, in UTC.
  final DateTime at;

  /// Where it came from.
  final LogStream stream;

  /// The line, masked, without its line ending.
  final String text;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'seq': seq,
    'step': step,
    'at': at.toUtc().toIso8601String(),
    'stream': stream.name,
    'text': text,
  };

  @override
  List<Object?> get props => [seq, step, at, stream, text];
}

/// Lines that were not delivered because the client read too slowly. They are
/// in the log: reconnect with `?after=<fromSeq - 1>` to read them.
final class LogGapFrame extends LogFrame {
  /// Creates the frame.
  const new({required this.fromSeq, required this.toSeq, required this.count});

  /// The wire name of this frame.
  static const frameType = 'gap';

  /// The `seq` of the first line that was dropped.
  final int fromSeq;

  /// The `seq` of the last line that was dropped.
  final int toSeq;

  /// How many lines were dropped.
  final int count;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'fromSeq': fromSeq,
    'toSeq': toSeq,
    'count': count,
  };

  @override
  List<Object?> get props => [fromSeq, toSeq, count];
}

/// The last frame: the job has ended and the log is complete.
final class LogEndFrame extends LogFrame {
  /// Creates the frame.
  const new({required this.state});

  /// The wire name of this frame.
  static const frameType = 'end';

  /// The state the job ended in.
  final JobState state;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {'type': frameType, 'state': state.wire};

  @override
  List<Object?> get props => [state];
}
