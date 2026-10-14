import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The connection of a runner to the engine, as the agent needs it: text
/// frames in and out, and why it ended. A class of its own so that the agent
/// is tested without sockets.
abstract interface class RunnerSocket {
  /// The text frames the engine sends. Ends when the connection does.
  Stream<String> get frames;

  /// Sends the text frame [text]. Throws if the connection is gone.
  void send(String text);

  /// Closes the connection.
  Future<void> close(int code, String reason);

  /// The close code the engine ended the connection with, once it ended.
  int? get closeCode;
}

/// Opens a connection to the engine.
typedef RunnerConnector = Future<RunnerSocket> Function();

/// A [RunnerSocket] over a [WebSocketChannel].
class ChannelRunnerSocket implements RunnerSocket {
  /// Wraps `channel`.
  new(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get frames =>
      _channel.stream.where((message) => message is String).cast<String>();

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close(int code, String reason) =>
      _channel.sink.close(code, reason);

  @override
  int? get closeCode => _channel.closeCode;
}
