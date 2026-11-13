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

const _mount = '/api/v1';

/// What a fake engine route does with a request.
typedef FakeRoute = FutureOr<void> Function(HttpRequest request, Call call);

/// A fake engine: an HTTP server on a loopback port that answers what the test
/// scripted and records what it was asked.
///
/// Like an engine of today, it serves the API under `/api/v1`: it answers the
/// client's probe (`GET /api/v1/version`) without recording it unless the
/// test scripted `GET /version`, routes and
/// records a request under `/api/v1` by its path within the API, and answers
/// `404` to every other path. One that is not [servesApiV1] is an engine
/// older than `/api/v1`: the probe is a request like any other.
class FakeEngine {
  new _(this._server, {required this.servesApiV1}) {
    _server.listen(_handle);
  }

  /// Starts a fake engine on a free loopback port.
  static Future<FakeEngine> start({bool servesApiV1 = true}) async =>
      FakeEngine._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        servesApiV1: servesApiV1,
      );

  /// Whether the API is under `/api/v1`, or at the root.
  final bool servesApiV1;

  /// The probes of `/api/v1` it answered.
  int probes = 0;

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
    final mounted = request.uri.path.startsWith('$_mount/');
    final probe =
        servesApiV1 &&
        request.method == 'GET' &&
        request.uri.path == '$_mount/version';
    if (probe) probes++;
    if (probe && !_routes.containsKey('GET /version')) {
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"version": "9.9.9", "apiVersion": "1"}');
      await request.response.close();
      return;
    }
    final call = Call(
      method: request.method,
      path: servesApiV1 && mounted
          ? request.uri.path.substring(_mount.length)
          : request.uri.path,
      query: request.uri.queryParameters,
      headers: {
        for (final name in const [
          'authorization',
          'user-agent',
          'content-type',
          'accept',
          'content-length',
          'x-content-sha256',
          'x-lease-id',
        ])
          name: ?request.headers.value(name),
      },
      body: body,
    );
    calls.add(call);
    final route = servesApiV1 && !mounted
        ? null
        : _routes['${call.method} ${call.path}'];
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
