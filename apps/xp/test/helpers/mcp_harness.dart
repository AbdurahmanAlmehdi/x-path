import 'dart:async';
import 'dart:convert';

/// Speaks MCP JSON-RPC, one message per line, to a server on two streams.
class McpHarness {
  new() {
    _outputController.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
  }

  final _input = StreamController<List<int>>();
  final _outputController = StreamController<List<int>>();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _notifications = <Map<String, dynamic>>[];
  int _nextId = 1;

  /// What the server reads (its standard input).
  Stream<List<int>> get input => _input.stream;

  /// Where the server writes (its standard output).
  StreamSink<List<int>> get output => _outputController.sink;

  /// Everything the server wrote that was not an answer to a request.
  List<Map<String, dynamic>> get notifications => _notifications;

  void _onLine(String line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    final id = message['id'];
    if (id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(message);
    } else {
      _notifications.add(message);
    }
  }

  /// Sends a request and returns the answer.
  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = _nextId++;
    final completer = _pending[id] = Completer();
    final message = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    _input.add(utf8.encode('${jsonEncode(message)}\n'));
    return completer.future.timeout(const Duration(seconds: 10));
  }

  /// Sends a notification.
  void notify(
    String method, [
    Map<String, Object?> params = const {},
  ]) => _input.add(
    utf8.encode(
      '${jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params})}\n',
    ),
  );

  /// Does the handshake and returns the `initialize` result.
  Future<Map<String, dynamic>> initialize() async {
    final answer = await request('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'test', 'version': '1'},
    });
    notify('notifications/initialized');
    return answer['result'] as Map<String, dynamic>;
  }

  /// Calls a tool and returns its `result`.
  Future<Map<String, dynamic>> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final answer = await request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return answer['result'] as Map<String, dynamic>;
  }

  /// Closes the server's input, as a client that exits does.
  Future<void> closeInput() => _input.close();
}
