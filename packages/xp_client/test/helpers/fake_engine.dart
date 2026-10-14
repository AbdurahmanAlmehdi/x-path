import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_api/xp_api.dart';

/// A request the fake engine received.
class Call {
  const new({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// What a fake engine route does with a request.
typedef FakeRoute = FutureOr<void> Function(HttpRequest request, Call call);

/// A fake engine: an HTTP server on a loopback port that answers what the test
/// scripted and records what it was asked.
class FakeEngine {
  new _(this._server) {
    _server.listen(_handle);
  }

  /// Starts a fake engine on a free loopback port.
  static Future<FakeEngine> start() async =>
      FakeEngine._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _routes = <String, FakeRoute>{};

  /// Every request, in the order they arrived.
  final calls = <Call>[];

  /// Where the engine listens.
  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  /// The last request.
  Call get last => calls.last;

  /// Scripts the answer to `METHOD /path`.
  void on(String method, String path, FakeRoute route) =>
      _routes['$method $path'] = route;

  /// Scripts a JSON answer to `METHOD /path`.
  void json(String method, String path, Object? body, {int status = 200}) =>
      on(method, path, (request, _) {
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
        return request.response.close();
      });

  /// Scripts an error envelope as the answer to `METHOD /path`.
  void error(String method, String path, ApiErrorCode code, String message) =>
      json(
        method,
        path,
        ErrorResponse.of(code, message).toJson(),
        status: code.statusCode,
      );

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final call = Call(
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      headers: {
        for (final name in const [
          'authorization',
          'user-agent',
          'content-type',
          'accept',
        ])
          name: ?request.headers.value(name),
      },
      body: body,
    );
    calls.add(call);
    final route = _routes['${call.method} ${call.path}'];
    if (route == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(
            ErrorResponse.of(ApiErrorCode.notFound, 'No route').toJson(),
          ),
        );
      await request.response.close();
      return;
    }
    await route(request, call);
  }
}
