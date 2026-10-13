import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

/// A response read to the end.
class RawResponse {
  const new(this.statusCode, this.contentType, this.body);

  final int statusCode;
  final String? contentType;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// A repository that cannot be read, so that every authenticated request
/// fails inside the engine.
class ThrowingDeviceTokenRepository implements DeviceTokenRepository {
  @override
  Future<List<DeviceToken>> list() async => throw StateError('disk on fire');

  @override
  Future<void> add(DeviceToken token) async {}
}

/// An engine on a free loopback port with everything in memory.
class TestEngine {
  new _({
    required this.server,
    required this.events,
    required this.clock,
    required this.tokens,
    required this.secret,
    required this.errors,
  });

  static Future<TestEngine> start({
    int eventCapacity = 100,
    EventLog Function(EventLog log)? wrapLog,
    DeviceTokenRepository? repository,
  }) async {
    final clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    final log = InMemoryEventLog(clock: clock, capacity: eventCapacity);
    final tokens = TokenService(
      tokens: repository ?? InMemoryDeviceTokenRepository(),
      clock: clock,
    );
    final errors = <Object>[];
    final issued = await tokens.issue(name: 'test', kind: DeviceTokenKind.app);
    final server = await XpdServer.start(
      tokens: tokens,
      events: wrapLog == null ? log : wrapLog(log),
      clock: clock,
      engineVersion: '9.9.9',
      onError: (error, _) => errors.add(error),
    );
    return ._(
      server: server,
      events: log,
      clock: clock,
      tokens: tokens,
      secret: issued.secret,
      errors: errors,
    );
  }

  final XpdServer server;
  final InMemoryEventLog events;
  final ManualClock clock;
  final TokenService tokens;

  /// A valid `app` token.
  final String secret;

  /// Exceptions that became 500 responses.
  final List<Object> errors;

  Uri get uri => server.uri;

  Future<void> close() => server.close();

  /// Sends a plain request. Sends the valid token unless [token] is given;
  /// pass an empty string for no `Authorization` header.
  Future<RawResponse> request(
    String path, {
    String method = 'GET',
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri.resolve(path));
      final bearer = token ?? secret;
      if (bearer.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $bearer');
      }
      headers.forEach(request.headers.set);
      final response = await request.close();
      return RawResponse(
        response.statusCode,
        response.headers.contentType?.toString(),
        await utf8.decodeStream(response),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Like [request] but with the headers of a WebSocket handshake, so that the
  /// engine answers with the real status instead of 426.
  Future<RawResponse> handshake(String path, {String? token}) => request(
    path,
    token: token,
    headers: {
      'connection': 'Upgrade',
      'upgrade': 'websocket',
      'sec-websocket-version': '13',
      'sec-websocket-key': base64.encode(List.filled(16, 7)),
    },
  );

  /// Opens the event stream.
  Future<EventStream> connect({int? after, String? token}) async {
    final query = after == null ? '' : '?after=$after';
    final bearer = token ?? secret;
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${uri.port}/events$query',
      headers: {if (bearer.isNotEmpty) 'authorization': 'Bearer $bearer'},
    );
    return EventStream(socket);
  }
}

/// The frames of one `/events` connection.
class EventStream {
  new(this.socket)
    : _frames = StreamQueue(
        socket.map(
          (frame) => SequencedEvent.fromJson(
            jsonDecode(frame as String) as Map<String, dynamic>,
          ),
        ),
      );

  final WebSocket socket;
  final StreamQueue<SequencedEvent> _frames;

  /// The next event, failing the test if none arrives.
  Future<SequencedEvent> next() =>
      _frames.next.timeout(const Duration(seconds: 5));

  /// The next [count] events.
  Future<List<SequencedEvent>> take(int count) async => [
    for (var i = 0; i < count; i++) await next(),
  ];

  /// Waits for the engine to close the socket and returns its close code.
  Future<int?> closeCode() async {
    expect(
      await _frames.hasNext.timeout(const Duration(seconds: 5)),
      isFalse,
      reason: 'the engine sent another frame instead of closing',
    );
    return socket.closeCode;
  }

  Future<void> close() async {
    await socket.close();
    await _frames.cancel(immediate: true);
  }
}

/// A [StringSink] that tells when something was written.
class WatchedSink implements StringSink {
  final _buffer = StringBuffer();
  final _waiters = <(Pattern, Completer<void>)>[];

  @override
  String toString() => _buffer.toString();

  /// Completes once the text written so far matches [pattern].
  Future<void> until(Pattern pattern) {
    if (_buffer.toString().contains(pattern)) return Future.value();
    final completer = Completer<void>();
    _waiters.add((pattern, completer));
    return completer.future.timeout(const Duration(seconds: 10));
  }

  @override
  void write(Object? object) {
    _buffer.write(object);
    final text = _buffer.toString();
    _waiters.removeWhere((waiter) {
      final matched = text.contains(waiter.$1);
      if (matched) waiter.$2.complete();
      return matched;
    });
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}
