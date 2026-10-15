import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xp_api/xp_api.dart';

/// One upload of an artifact the fake engine received.
class ReceivedArtifact {
  /// Creates the record.
  const new({
    required this.jobId,
    required this.name,
    required this.headers,
    required this.query,
    required this.bytes,
  });

  /// The job in the path.
  final String jobId;

  /// The name in the path.
  final String name;

  /// The request headers, names in lower case.
  final Map<String, String> headers;

  /// The query parameters.
  final Map<String, String> query;

  /// The body.
  final List<int> bytes;
}

/// One connection of a runner to the fake engine; the test plays the engine.
class EngineSession {
  /// Wraps the accepted [socket].
  new(this.socket) {
    socket.listen(
      (message) {
        if (message is String) {
          _arrived(
            RunnerFrame.fromJson(jsonDecode(message) as Map<String, dynamic>),
          );
        }
      },
      onDone: () {
        closeCode = socket.closeCode;
        _closed.complete();
      },
    );
  }

  /// The WebSocket.
  final WebSocket socket;

  /// The frames received and not taken yet.
  final received = <RunnerFrame>[];

  final _waiting = <(bool Function(RunnerFrame), Completer<RunnerFrame>)>[];
  final _closed = Completer<void>();

  /// The code the runner closed the connection with, once it did.
  int? closeCode;

  /// Completes when the runner closed the connection.
  Future<void> get closed => _closed.future;

  void _arrived(RunnerFrame frame) {
    for (final entry in _waiting.toList()) {
      if (entry.$1(frame)) {
        _waiting.remove(entry);
        entry.$2.complete(frame);
        return;
      }
    }
    received.add(frame);
  }

  /// Sends [frame] to the runner.
  void send(EngineFrame frame) => socket.add(jsonEncode(frame.toJson()));

  /// The next frame of type [T], waiting for it if it did not come yet.
  Future<T> next<T extends RunnerFrame>({
    Duration timeout = const Duration(seconds: 30),
    bool Function(T frame)? where,
  }) {
    bool matches(RunnerFrame frame) =>
        frame is T && (where == null || where(frame));
    final index = received.indexWhere(matches);
    if (index >= 0) return Future.value(received.removeAt(index) as T);
    final completer = Completer<RunnerFrame>();
    _waiting.add((matches, completer));
    return completer.future
        .timeout(timeout, onTimeout: () => throw TimeoutException('A $T'))
        .then((frame) => frame as T);
  }

  /// Closes the connection with [code].
  Future<void> close([int? code]) => socket.close(code);
}

/// An engine, as far as a runner needs one: the WebSocket it dials and the
/// upload of artifacts, on a loopback port. The test plays the engine.
class FakeRunnerEngine {
  new _(this._server, this.credential) {
    _server.listen(_handle);
  }

  /// Starts the engine; only [credential] is accepted as the token.
  static Future<FakeRunnerEngine> start({
    String credential = 'xpr_credential',
  }) async => FakeRunnerEngine._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    credential,
  );

  final HttpServer _server;

  /// The token the engine accepts.
  final String credential;

  final _sessions = <EngineSession>[];
  final _waiting = <Completer<EngineSession>>[];

  /// The artifacts received.
  final artifacts = <ReceivedArtifact>[];

  /// The status the upload answers with.
  int uploadStatus = 201;

  /// The status the connection answers with when it is not an upgrade.
  int connectStatus = 200;

  /// The runner bundle `GET /runners/bundle` serves, or `null` for a `404`.
  List<int>? bundle;

  /// The SHA-256 the bundle download announces; the real one when `null`.
  String? bundleSha256;

  /// The `os` and `arch` of every bundle download, with the token it came
  /// with.
  final bundleRequests = <({String os, String arch, String? authorization})>[];

  /// Where a runner reaches this engine.
  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  /// The next connection of a runner, also one that was made already.
  Future<EngineSession> get connection {
    if (_sessions.isNotEmpty) return Future.value(_sessions.removeAt(0));
    final waiting = Completer<EngineSession>();
    _waiting.add(waiting);
    return waiting.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('A runner connection'),
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final token = request.headers.value('authorization');
    if (token != 'Bearer $credential') {
      request.response.statusCode = 401;
      request.response.write(
        jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'Not accepted.'},
        }),
      );
      await request.response.close();
      return;
    }
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/runners/bundle') {
      await _serveBundle(request);
      return;
    }
    if (path == '/runners/connect') {
      if (connectStatus != 200) {
        request.response.statusCode = connectStatus;
        request.response.write(
          jsonEncode({
            'error': {'code': 'forbidden', 'message': 'Not a runner token.'},
          }),
        );
        await request.response.close();
        return;
      }
      final session = EngineSession(
        await WebSocketTransformer.upgrade(request),
      );
      if (_waiting.isEmpty) {
        _sessions.add(session);
      } else {
        _waiting.removeAt(0).complete(session);
      }
      return;
    }
    if (request.method == 'PUT' && path.startsWith('/runners/jobs/')) {
      final parts = path.split('/');
      final bytes = await request.expand((chunk) => chunk).toList();
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name] = values.first);
      artifacts.add(
        ReceivedArtifact(
          jobId: parts[3],
          name: parts[5],
          headers: headers,
          query: request.uri.queryParameters,
          bytes: bytes,
        ),
      );
      request.response.statusCode = uploadStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          uploadStatus == 201
              ? {
                  'id': 'art_1',
                  'jobId': parts[3],
                  'kind': request.uri.queryParameters['kind'],
                  'name': parts[5],
                  'size': bytes.length,
                  'sha256': headers['x-content-sha256'],
                  'pinned': false,
                  'createdAt': '2026-10-14T12:00:00Z',
                }
              : {
                  'error': {'code': 'conflict', 'message': 'No lease.'},
                },
        ),
      );
      await request.response.close();
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void> _serveBundle(HttpRequest request) async {
    bundleRequests.add((
      os: request.uri.queryParameters['os'] ?? '',
      arch: request.uri.queryParameters['arch'] ?? '',
      authorization: request.headers.value('authorization'),
    ));
    final bytes = bundle;
    if (bytes == null) {
      request.response
        ..statusCode = 404
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': {
              'code': 'not_found',
              'message': 'This engine has no runner bundle for this machine.',
            },
          }),
        );
    } else {
      request.response
        ..headers.contentType = ContentType('application', 'gzip')
        ..headers.set(
          'x-content-sha256',
          bundleSha256 ?? sha256.convert(bytes).toString(),
        )
        ..headers.contentLength = bytes.length
        ..add(bytes);
    }
    await request.response.close();
  }

  /// Stops the engine and closes the connections.
  Future<void> close() async {
    await _server.close(force: true);
  }
}
