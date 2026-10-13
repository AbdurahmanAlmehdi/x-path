import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_adapters/src/stores/play/play_token_provider.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [FirebaseAppDistribution] over the Firebase App Distribution REST API
/// (v1; D-16).
///
/// Every call carries an access token from a [PlayTokenProvider] (the OAuth2
/// JWT bearer flow of the service account, here with the `cloud-platform`
/// scope). A `401` makes the client drop the token and try once more with a
/// new one.
///
/// A binary goes up with the simple media upload (`releases:upload` under
/// `/upload/v1`, `X-Goog-Upload-Protocol: raw`), streamed from the artifact
/// store with a known length, so an IPA of hundreds of megabytes is never held
/// in memory. The answer is a long-running operation, which the step polls
/// with [operation].
///
/// Retries: a `429` is waited out if Google says to wait no longer than
/// [maxWait] (`Retry-After`, else exponential backoff) and retried up to
/// [maxAttempts] times; a longer wait ends in a
/// [FirebaseRateLimitedException]. A `5xx` is retried the same way for reads
/// and for the calls that repeat safely (release notes, distribution); **not
/// for an upload**, which may have gone through: `alreadyDone` finds out.
class HttpFirebaseAppDistribution implements FirebaseAppDistribution {
  /// Creates a client for the service account [account].
  ///
  /// The API is `https://firebaseappdistribution.googleapis.com`; [client] and
  /// [sleep] are for tests.
  new({
    required PlayServiceAccount account,
    required Clock clock,
    http.Client? client,
    Uri? baseUrl,
    this.maxAttempts = 3,
    this.maxWait = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 60),
    this.uploadTimeout = const Duration(minutes: 30),
    Future<void> Function(Duration)? sleep,
  }) : _client = client ?? http.Client(),
       _baseUrl =
           baseUrl ??
           Uri.parse('https://firebaseappdistribution.googleapis.com'),
       _sleep = sleep ?? Future.delayed {
    _tokens = PlayTokenProvider(
      account: account,
      clock: clock,
      scope: cloudPlatformScope,
      client: _client,
      timeout: timeout,
    );
  }

  /// How many times a call is made before a `429` or a `5xx` is given up on.
  final int maxAttempts;

  /// The longest the client waits between two attempts.
  final Duration maxWait;

  /// How long one request has to be answered.
  final Duration timeout;

  /// How long an upload may take.
  final Duration uploadTimeout;

  final http.Client _client;
  final Uri _baseUrl;
  final Future<void> Function(Duration) _sleep;
  late final PlayTokenProvider _tokens;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  Future<void> verifyAccess() async {
    await _token();
  }

  @override
  Future<FirebaseOperation> uploadRelease(
    String appName, {
    required Stream<List<int>> Function() content,
    required int length,
    required String fileName,
  }) async {
    final response = await _send(
      'POST',
      _baseUrl.replace(path: '/upload/v1/$appName/releases:upload'),
      content: content,
      length: length,
      headers: {
        'X-Goog-Upload-Protocol': 'raw',
        'X-Goog-Upload-File-Name': Uri.encodeComponent(fileName),
      },
      timeout: uploadTimeout,
    );
    return _operation(_decode(response));
  }

  @override
  Future<FirebaseOperation> operation(String name) async => _operation(
    _decode(
      await _send(
        'GET',
        _baseUrl.replace(path: '/v1/$name'),
        retryServerErrors: true,
      ),
    ),
  );

  @override
  Future<List<FirebaseRelease>> releases(
    String appName, {
    int pages = 1,
  }) async {
    final releases = <FirebaseRelease>[];
    String? pageToken;
    for (var page = 0; page < pages; page++) {
      final json = _decode(
        await _send(
          'GET',
          _baseUrl.replace(
            path: '/v1/$appName/releases',
            queryParameters: {
              'pageSize': '100',
              'orderBy': 'createTime desc',
              'pageToken': ?pageToken,
            },
          ),
          retryServerErrors: true,
        ),
      );
      releases.addAll([
        for (final release in _objects(json['releases'])) _release(release),
      ]);
      pageToken = _text(json['nextPageToken']);
      if (pageToken == null || pageToken.isEmpty) break;
    }
    return releases;
  }

  @override
  Future<FirebaseRelease> updateReleaseNotes(
    String releaseName,
    String text,
  ) async => _release(
    _decode(
      await _send(
        'PATCH',
        _baseUrl.replace(
          path: '/v1/$releaseName',
          queryParameters: {'updateMask': 'releaseNotes.text'},
        ),
        body: {
          'releaseNotes': {'text': text},
        },
        retryServerErrors: true,
      ),
    ),
  );

  @override
  Future<void> distribute(
    String releaseName, {
    List<String> testerEmails = const [],
    List<String> groupAliases = const [],
  }) async {
    await _send(
      'POST',
      _baseUrl.replace(path: '/v1/$releaseName:distribute'),
      body: {
        if (testerEmails.isNotEmpty) 'testerEmails': testerEmails,
        if (groupAliases.isNotEmpty) 'groupAliases': groupAliases,
      },
      retryServerErrors: true,
    );
  }

  /// The access token. Failures of the token endpoint become the exceptions
  /// of this API, so that callers handle one family.
  Future<String> _token() async {
    try {
      return await _tokens.token();
    } on PlayAuthException catch (error) {
      throw FirebaseAuthException(error.message, reason: error.reason);
    } on PlayServerException catch (error) {
      throw FirebaseServerException(
        error.statusCode,
        error.message,
        reason: error.reason,
      );
    }
  }

  /// Calls the API and returns the successful response.
  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, Object?>? body,
    Stream<List<int>> Function()? content,
    int? length,
    Map<String, String> headers = const {},
    Duration? timeout,
    bool retryServerErrors = false,
  }) async {
    var refreshed = false;
    for (var attempt = 1; ; attempt++) {
      final request = _request(
        method,
        url,
        await _token(),
        body,
        content,
        length,
        headers,
      );
      final http.Response response;
      try {
        response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout ?? this.timeout),
        );
      } on TimeoutException {
        throw const FirebaseServerException(
          0,
          'Firebase App Distribution did not answer in time.',
        );
      } on http.ClientException catch (error) {
        throw FirebaseServerException(
          0,
          'Firebase App Distribution is not reachable: $error',
        );
      }
      final status = response.statusCode;
      if (status >= 200 && status < 300) return response;

      if (status == 401 && !refreshed) {
        // The token may have been revoked before it expired.
        refreshed = true;
        _tokens.invalidate();
        attempt--;
        continue;
      }
      final retryAfter = _retryAfter(response);
      final wait = retryAfter ?? Duration(seconds: 1 << (attempt - 1));
      final retryable = status == 429 || (status >= 500 && retryServerErrors);
      if (retryable && attempt < maxAttempts && wait <= maxWait) {
        await _sleep(wait);
        continue;
      }
      throw _error(response, retryAfter);
    }
  }

  http.BaseRequest _request(
    String method,
    Uri url,
    String token,
    Map<String, Object?>? body,
    Stream<List<int>> Function()? content,
    int? length,
    Map<String, String> extraHeaders,
  ) {
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'User-Agent': 'xpath',
      ...extraHeaders,
    };
    if (content != null) {
      final request = http.StreamedRequest(method, url)
        ..followRedirects = false
        ..contentLength = length
        ..headers.addAll({
          ...headers,
          'Content-Type': 'application/octet-stream',
        });
      unawaited(
        request.sink.addStream(content()).whenComplete(request.sink.close),
      );
      return request;
    }
    final request = http.Request(method, url)
      ..followRedirects = false
      ..headers.addAll({
        ...headers,
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    return request;
  }

  Duration? _retryAfter(http.Response response) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return const {};
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on Object {
      throw FirebaseServerException(
        response.statusCode,
        'Firebase App Distribution answered with something that is not a '
        'JSON object.',
      );
    }
  }

  // Errors.

  FirebaseException _error(http.Response response, Duration? retryAfter) {
    final (message, reason) = _errorMessage(response);
    return switch (response.statusCode) {
      401 => FirebaseAuthException(message, reason: reason),
      403 => FirebaseForbiddenException(message, reason: reason),
      404 => FirebaseNotFoundException(message, reason: reason),
      429 => FirebaseRateLimitedException(
        message,
        reason: reason,
        retryAfter: retryAfter,
      ),
      >= 500 => FirebaseServerException(
        response.statusCode,
        message,
        reason: reason,
      ),
      _ => FirebaseValidationException(
        response.statusCode,
        message,
        reason: reason,
      ),
    };
  }

  /// The message and the status of a Google error body: `error.message` and
  /// `error.status` (`PERMISSION_DENIED`, `INVALID_ARGUMENT`, ...).
  (String, String?) _errorMessage(http.Response response) {
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>;
      return (
        _text(error['message']) ?? 'Firebase App Distribution refused.',
        _text(error['status']),
      );
    } on Object {
      return (
        'Firebase App Distribution refused (HTTP ${response.statusCode}).',
        null,
      );
    }
  }

  // The resources.

  List<Map<String, dynamic>> _objects(Object? value) => [
    if (value is List<dynamic>)
      for (final item in value)
        if (item is Map<String, dynamic>) item,
  ];

  String? _text(Object? value) => value is String ? value : null;

  FirebaseOperation _operation(Map<String, dynamic> json) {
    final name = _text(json['name']);
    if (name == null || name.isEmpty) {
      throw const FirebaseServerException(
        0,
        'Firebase App Distribution sent no operation name.',
      );
    }
    final error = json['error'];
    final response = json['response'];
    final release = response is Map<String, dynamic>
        ? response['release']
        : null;
    return FirebaseOperation(
      name: name,
      done: json['done'] == true,
      release: release is Map<String, dynamic> ? _release(release) : null,
      result: FirebaseUploadResult.fromWire(
        response is Map<String, dynamic> ? _text(response['result']) : null,
      ),
      error: error is Map<String, dynamic>
          ? _text(error['message']) ?? 'The upload failed.'
          : null,
    );
  }

  FirebaseRelease _release(Map<String, dynamic> json) {
    final name = _text(json['name']);
    if (name == null || name.isEmpty) {
      throw const FirebaseServerException(
        0,
        'Firebase App Distribution sent a release without a name.',
      );
    }
    final notes = json['releaseNotes'];
    return FirebaseRelease(
      name: name,
      displayVersion: _text(json['displayVersion']),
      buildVersion: _text(json['buildVersion']),
      releaseNotes: notes is Map<String, dynamic> ? _text(notes['text']) : null,
      firebaseConsoleUri: _text(json['firebaseConsoleUri']),
      testingUri: _text(json['testingUri']),
    );
  }
}
