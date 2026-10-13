import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// One line of a process's output.
class OutputLine extends Equatable {
  /// Creates a line.
  const new({
    required this.seq,
    required this.timestamp,
    required this.stream,
    required this.text,
  });

  /// Position in the output of the process, from 1, across both streams.
  final int seq;

  /// When the engine read the line, in UTC.
  final DateTime timestamp;

  /// Which stream it came from.
  final LogStream stream;

  /// The line without its line ending. Already masked.
  final String text;

  @override
  List<Object?> get props => [seq, timestamp, stream, text];
}
