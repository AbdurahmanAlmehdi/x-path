import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_client/xp_client.dart';

import 'fake_web_socket.dart';

/// A [WebSocketConnector] that hands out what the test lined up, one thing per
/// connection attempt: a [FakeWebSocket], or an exception to throw. When
/// nothing is left it waits, so a stream stays quiet until the test cancels
/// it.
class ScriptedConnector {
  final _attempts = <Object>[];

  /// The URI of every attempt.
  final uris = <Uri>[];

  /// The query `after` of every attempt, as the engine would see it.
  List<String?> get afters => [
    for (final uri in uris) uri.queryParameters['after'],
  ];

  /// Lines up a socket for the next attempt and returns it.
  FakeWebSocket socket() {
    final socket = FakeWebSocket();
    _attempts.add(socket);
    return socket;
  }

  /// Lines up a failure for the next attempt.
  void fail(Exception error) => _attempts.add(error);

  /// Lines up an attempt that completes when [gate] does, with [socket].
  void hold(Completer<WebSocketChannel> gate) => _attempts.add(gate);

  Future<WebSocketChannel> call(Uri uri, Map<String, String> headers) {
    uris.add(uri);
    if (_attempts.isEmpty) return Completer<WebSocketChannel>().future;
    return switch (_attempts.removeAt(0)) {
      final Exception error => Future.error(error),
      final Completer<WebSocketChannel> gate => gate.future,
      final FakeWebSocket socket => Future.value(socket),
      _ => throw StateError('unreachable'),
    };
  }
}
