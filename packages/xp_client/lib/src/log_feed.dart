import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/src/socket_feed.dart';

/// The feed behind `XpClient.followJobLogs`: `GET /jobs/{id}/logs`, resumed
/// with `after=<seq of the last line handled>`.
///
/// It emits the lines in order, each once, and the end frame last. A `gap`
/// frame (the client read too slowly) is not passed on: the feed reconnects
/// from the line before the gap and so reads the lines it missed.
class LogFeed extends SocketFeed<LogFrame> {
  /// Creates the feed. It opens connections with `connect` and resumes after
  /// the line `after`.
  new({
    required this._connect,
    required int after,
    required super.delay,
    required super.initialDelay,
    required super.maxDelay,
  }) : _cursor = after;

  final Future<WebSocketChannel> Function(int after) _connect;
  int _cursor;

  @override
  Future<WebSocketChannel> open() => _connect(_cursor);

  @override
  FeedNext handle(Map<String, dynamic> frame, void Function(LogFrame) emit) {
    switch (LogFrame.fromJson(frame)) {
      case final LogLineFrame line:
        if (line.seq <= _cursor) return FeedNext.read;
        _cursor = line.seq;
        emit(line);
        return FeedNext.read;
      case LogGapFrame():
        return FeedNext.reconnect;
      case final LogEndFrame end:
        emit(end);
        return FeedNext.finish;
    }
  }
}
