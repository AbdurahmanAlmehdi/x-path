import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/responses.dart';

/// WebSocket close code for a normal closure (RFC 6455).
const _normalClosure = 1000;

/// `GET /runners/connect`: the WebSocket a runner dials out on (D-08).
///
/// The runner authenticates with its credential as the bearer token, before
/// the upgrade; any other kind of token answers `403`. Every text frame is a
/// JSON `RunnerFrame` (runner to engine) or `EngineFrame` (engine to runner);
/// the protocol is the `RunnerHub`'s. The engine pings every 30 seconds.
class RunnerConnectRoute {
  /// Creates the route.
  new({required this._runners, required this._hub});

  final RunnerService _runners;
  final RunnerHub _hub;
  final _sockets = <WebSocketChannel>{};

  /// Handles the request: validates it, then upgrades.
  Future<Response> handle(Request request) async {
    if (!_isUpgrade(request)) {
      return errorResponse(
        ApiErrorCode.upgradeRequired,
        'This route only speaks WebSocket.',
      );
    }
    final RunnerRecord runner;
    try {
      runner = await _runners.runnerFor(deviceTokenOf(request));
    } on RunnerForbiddenException catch (error) {
      return errorResponse(ApiErrorCode.forbidden, error.message);
    }
    return await webSocketHandler(
      (channel, _) => _onConnection(channel, runner),
      // Browsers always send Origin. No browser may talk to the engine.
      allowedOrigins: const [],
      pingInterval: const Duration(seconds: 30),
    )(request);
  }

  /// Closes every open runner socket.
  Future<void> closeSockets() async {
    final open = _sockets.toList();
    for (final socket in open) {
      unawaited(socket.sink.close(_normalClosure, 'engine shutting down'));
    }
    await Future.wait<void>(open.map((socket) => socket.sink.done))
        .timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
  }

  void _onConnection(WebSocketChannel channel, RunnerRecord runner) {
    _sockets.add(channel);
    unawaited(channel.sink.done.whenComplete(() => _sockets.remove(channel)));
    final link = _SocketLink(channel);
    final connection = _hub.connect(runner, link);
    channel.stream.listen(
      (message) {
        if (message is String) {
          unawaited(connection.receiveText(message));
        } else {
          unawaited(
            link.close(runnerProtocolCloseCode, 'frames are text, not binary'),
          );
        }
      },
      onError: (Object _) {},
      onDone: () => unawaited(connection.closed()),
    );
  }
}

class _SocketLink implements RunnerLink {
  new(this._channel);

  final WebSocketChannel _channel;

  @override
  void send(EngineFrame frame) => _channel.sink.add(jsonEncode(frame.toJson()));

  @override
  Future<void> close(int code, String reason) =>
      _channel.sink.close(code, reason);
}

bool _isUpgrade(Request request) {
  final connection = request.headers['connection']?.toLowerCase() ?? '';
  return request.headers['upgrade']?.toLowerCase() == 'websocket' &&
      connection.split(',').map((t) => t.trim()).contains('upgrade');
}
