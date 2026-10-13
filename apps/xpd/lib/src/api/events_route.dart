import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/responses.dart';

/// WebSocket close code for a normal closure (RFC 6455). The `web_socket`
/// package does not let a sender use 1001 (going away).
const _normalClosure = 1000;

/// `GET /events`: the engine event stream over a WebSocket.
///
/// Clients authenticate with the bearer header before the upgrade. Each text
/// frame is a JSON [SequencedEvent]; the first one is `stream.opened`.
class EventsRoute {
  /// Creates the route over an event log.
  new({required this._events, required this._clock});

  final EventLog _events;
  final Clock _clock;
  final _sockets = <WebSocketChannel>{};

  /// Handles the request: validates it, then upgrades.
  FutureOr<Response> handle(Request request) {
    if (!_isUpgrade(request)) {
      return errorResponse(
        ApiErrorCode.upgradeRequired,
        'This route only speaks WebSocket.',
      );
    }
    final param = request.url.queryParameters['after'];
    final after = param == null ? null : int.tryParse(param);
    if (param != null && (after == null || after < 0)) {
      return errorResponse(
        ApiErrorCode.invalidRequest,
        'after must be a non-negative integer.',
      );
    }
    if (after != null && !_events.canResume(after)) {
      return errorResponse(
        ApiErrorCode.resyncRequired,
        'Event $after is outside the resume window; reload and reconnect '
        'without after.',
      );
    }
    return webSocketHandler(
      (channel, _) => _onConnection(channel, after),
      // Browsers always send Origin. No browser may talk to the engine.
      allowedOrigins: const [],
      pingInterval: const Duration(seconds: 30),
    )(request);
  }

  /// Ends the event log subscriptions and waits for the sockets to close.
  Future<void> closeSockets() async {
    final open = _sockets.map((socket) => socket.sink.done).toList();
    await _events.close();
    await Future.wait<void>(open)
        .timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
  }

  void _onConnection(WebSocketChannel channel, int? after) {
    _sockets.add(channel);
    unawaited(channel.sink.done.whenComplete(() => _sockets.remove(channel)));
    _send(
      channel,
      SequencedEvent(
        seq: _events.head,
        at: _clock.now(),
        event: const StreamOpened(),
      ),
    );
    final subscription = _events
        .subscribe(after: after)
        .listen(
          (event) => _send(channel, event),
          onError: (Object _) =>
              channel.sink.close(eventStreamResyncCloseCode, 'resync required'),
          onDone: () =>
              channel.sink.close(_normalClosure, 'engine shutting down'),
        );
    // Clients do not talk; we only watch for them leaving.
    channel.stream.listen(
      (_) {},
      onError: (Object _) {},
      onDone: () => unawaited(subscription.cancel()),
    );
  }

  void _send(WebSocketChannel channel, SequencedEvent event) =>
      channel.sink.add(jsonEncode(event.toJson()));
}

bool _isUpgrade(Request request) {
  final connection = request.headers['connection']?.toLowerCase() ?? '';
  return request.headers['upgrade']?.toLowerCase() == 'websocket' &&
      connection.split(',').map((t) => t.trim()).contains('upgrade');
}
