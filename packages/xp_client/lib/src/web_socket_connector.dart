import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_client/src/exceptions.dart';

/// Opens a WebSocket to [uri] with [headers].
///
/// An engine that refuses the upgrade with an error response, for example
/// `409 resync_required`, makes it throw the matching [ApiException].
typedef WebSocketConnector = Future<WebSocketChannel> Function(
  Uri uri,
  Map<String, String> headers,
);

/// The [WebSocketConnector] over `dart:io`.
///
/// It does the upgrade by hand instead of with `WebSocket.connect`, which
/// throws away the body of a refusal: the body is the error envelope that says
/// why (a cursor the engine can no longer resume).
Future<WebSocketChannel> connectWebSocket(
  Uri uri,
  Map<String, String> headers,
) async {
  // The engine is on this machine or on the owner's network: no proxy.
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final key = base64.encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final request = await client.getUrl(
      uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
    );
    headers.forEach(request.headers.set);
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', key)
      ..set('Sec-WebSocket-Version', '13');
    final response = await request.close();
    if (response.statusCode != HttpStatus.switchingProtocols) {
      final body = await utf8.decodeStream(response);
      throw ApiException.fromResponse(response.statusCode, body);
    }
    final accept = response.headers.value('Sec-WebSocket-Accept');
    if (accept != WebSocketChannel.signKey(key)) {
      throw const ConnectionException(
        'The engine did not complete the WebSocket handshake.',
      );
    }
    final socket = await response.detachSocket();
    final webSocket = WebSocket.fromUpgradedSocket(socket, serverSide: false);
    return IOWebSocketChannel(webSocket);
  } on XpClientException {
    rethrow;
  } on Object catch (error) {
    throw ConnectionException('Cannot reach the engine: $error', cause: error);
  } finally {
    // The upgraded socket is detached from the client, so this ends nothing
    // that is still in use.
    client.close(force: true);
  }
}
