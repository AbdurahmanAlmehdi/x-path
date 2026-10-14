import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';

/// A WebSocket the test drives: [send] frames to the client, [dropWith] closes
/// it from the server's side, [closedByClient] says whether the client left.
class FakeWebSocket extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  new() {
    _sink = _FakeSink(this);
  }

  final _incoming = StreamController<dynamic>();
  late final _FakeSink _sink;
  int? _closeCode;

  /// Whether the client closed its end.
  bool closedByClient = false;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  /// Sends a text frame.
  void send(Object frame) =>
      _incoming.add(frame is String ? frame : jsonEncode(frame));

  /// Sends an event frame.
  void sendEvent(SequencedEvent event) => send(event.toJson());

  /// Sends an error to the client's listener.
  void fail(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }

  /// Closes the connection from the server's side with [code].
  Future<void> dropWith([int? code]) {
    _closeCode = code;
    return _incoming.close();
  }
}

class _FakeSink implements WebSocketSink {
  new(this._socket);

  final FakeWebSocket _socket;
  final _done = Completer<void>();

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _socket.closedByClient = true;
    if (!_done.isCompleted) _done.complete();
    if (!_socket._incoming.isClosed) unawaited(_socket._incoming.close());
  }

  @override
  Future<void> get done => _done.future;

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
}
