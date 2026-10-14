import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/jobs/jobs_routes.dart';
import 'package:xpd/src/api/responses.dart';

/// WebSocket close code for a normal closure (RFC 6455).
const _normalClosure = 1000;

/// `GET /jobs/{id}/logs`: the log lines of a job over a WebSocket.
///
/// Like `/events`: clients authenticate with the bearer header before the
/// upgrade, each text frame is JSON (a `LogFrame`), and a client that saw
/// line `seq` reconnects with `?after=<seq>`. The route replays the log from
/// the cursor, then follows the job live. A client that reads too slowly gets
/// a `gap` frame for the lines it missed (the log has them), never an
/// unbounded queue in the engine. The last frame is `end`, with the state the
/// job is in, and the socket closes with code 1000.
class JobLogsRoute {
  /// Creates the route over the jobs and their logs.
  new({required this._jobs, required this._logs});

  final JobControl _jobs;
  final JobLogs _logs;
  final _sockets = <WebSocketChannel>{};

  /// Handles the request for the logs of job [id]: validates it, then
  /// upgrades.
  Future<Response> handle(Request request, String id) => guardJobs(() async {
    if (!_isUpgrade(request)) {
      return errorResponse(
        ApiErrorCode.upgradeRequired,
        'This route only speaks WebSocket.',
      );
    }
    final param = request.url.queryParameters['after'];
    final after = param == null ? 0 : int.tryParse(param);
    if (after == null || after < 0) {
      return errorResponse(
        ApiErrorCode.invalidRequest,
        'after must be a non-negative integer.',
      );
    }
    await _jobs.get(id);
    if (after > await _logs.head(id)) {
      return errorResponse(
        ApiErrorCode.resyncRequired,
        'Line $after is beyond the log of job $id; reconnect without after.',
      );
    }
    return await webSocketHandler(
      (channel, _) => _onConnection(channel, id, after),
      // Browsers always send Origin. No browser may talk to the engine.
      allowedOrigins: const [],
      pingInterval: const Duration(seconds: 30),
    )(request);
  });

  /// Closes every open log socket.
  Future<void> closeSockets() async {
    final open = _sockets.toList();
    for (final socket in open) {
      unawaited(socket.sink.close(_normalClosure, 'engine shutting down'));
    }
    await Future.wait<void>(open.map((socket) => socket.sink.done))
        .timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
  }

  void _onConnection(WebSocketChannel channel, String id, int after) {
    _sockets.add(channel);
    unawaited(channel.sink.done.whenComplete(() => _sockets.remove(channel)));
    final subscription = _logs
        .follow(id, after: after)
        .listen(
          (event) => _send(channel, _frame(event)),
          onDone: () async {
            final job = await _jobs.get(id);
            _send(channel, LogEndFrame(state: job.state));
            await channel.sink.close(_normalClosure, 'end of log');
          },
        );
    // Clients do not talk; we only watch for them leaving.
    channel.stream.listen(
      (_) {},
      onError: (Object _) {},
      onDone: () => unawaited(subscription.cancel()),
    );
  }

  LogFrame _frame(FanOutEvent<LogLineFrame> event) => switch (event) {
    FanOutItem(:final value) => value,
    FanOutGap(:final fromSeq, :final toSeq, :final count) => LogGapFrame(
      fromSeq: fromSeq,
      toSeq: toSeq,
      count: count,
    ),
  };

  void _send(WebSocketChannel channel, LogFrame frame) =>
      channel.sink.add(jsonEncode(frame.toJson()));
}

bool _isUpgrade(Request request) {
  final connection = request.headers['connection']?.toLowerCase() ?? '';
  return request.headers['upgrade']?.toLowerCase() == 'websocket' &&
      connection.split(',').map((t) => t.trim()).contains('upgrade');
}
