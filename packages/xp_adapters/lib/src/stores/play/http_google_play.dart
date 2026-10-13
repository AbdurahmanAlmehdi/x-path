import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_adapters/src/stores/play/play_token_provider.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [GooglePlay] over the Google Play Developer API (androidpublisher v3).
///
/// Every call carries an access token from a [PlayTokenProvider] (OAuth2 JWT
/// bearer flow of the service account). A `401` makes the client drop the
/// token and try once more with a new one.
///
/// Bundles are uploaded with the simple media upload (`uploadType=media`),
/// streamed from the artifact store with a known length, so a bundle of
/// hundreds of megabytes is never held in memory.
///
/// [commitEdit] always sends `changesInReviewBehavior=ERROR_IF_IN_REVIEW`
/// (D-15): a review in progress is never cancelled, and the call fails with a
/// [PlayReviewInProgressException] instead.
///
/// Retries: a `429` is waited out if Google says to wait no longer than
/// [maxWait] (`Retry-After`, else exponential backoff) and retried up to
/// [maxAttempts] times; a longer wait ends in a [PlayRateLimitedException].
/// A `5xx` is retried the same way for reads and for the calls that repeat
/// safely (track update, delete); a `5xx` on an upload or a commit is not,
/// because it may have gone through: the step's `alreadyDone` finds out.
class HttpGooglePlay implements GooglePlay {
  /// Creates a client for the service account [account].
  ///
  /// The API is `https://androidpublisher.googleapis.com` and uploads go to
  /// the same host unless a test says otherwise; [client] and [sleep] are for
  /// tests.
  new({
    required PlayServiceAccount account,
    required Clock clock,
    http.Client? client,
    Uri? apiBaseUrl,
    Uri? uploadBaseUrl,
    this.maxAttempts = 3,
    this.maxWait = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 60),
    this.uploadTimeout = const Duration(minutes: 30),
    Future<void> Function(Duration)? sleep,
  }) : _client = client ?? http.Client(),
       _apiBaseUrl =
           apiBaseUrl ?? Uri.parse('https://androidpublisher.googleapis.com'),
       _uploadBaseUrl =
           uploadBaseUrl ??
           apiBaseUrl ??
           Uri.parse('https://androidpublisher.googleapis.com'),
       _sleep = sleep ?? Future.delayed {
    _tokens = PlayTokenProvider(
      account: account,
      clock: clock,
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
  final Uri _apiBaseUrl;
  final Uri _uploadBaseUrl;
  final Future<void> Function(Duration) _sleep;
  late final PlayTokenProvider _tokens;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  Future<PlayEdit> insertEdit(String packageName) async {
    final json = await _json('POST', _edits(packageName), body: const {});
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const PlayServerException(0, 'Google Play sent no edit id.');
    }
    final seconds = int.tryParse('${json['expiryTimeSeconds']}');
    return PlayEdit(
      id: id,
      expiresAt: seconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    );
  }

  @override
  Future<void> deleteEdit(String packageName, String editId) async {
    await _send('DELETE', _edit(packageName, editId), retryServerErrors: true);
  }

  @override
  Future<PlayBundle> uploadBundle(
    String packageName,
    String editId, {
    required Stream<List<int>> Function() content,
    required int length,
  }) async {
    final url = _uploadBaseUrl.replace(
      path:
          '/upload/androidpublisher/v3/applications/'
          '${Uri.encodeComponent(packageName)}/edits/'
          '${Uri.encodeComponent(editId)}/bundles',
      queryParameters: {'uploadType': 'media'},
    );
    final response = await _send(
      'POST',
      url,
      content: content,
      length: length,
      timeout: uploadTimeout,
    );
    return _bundle(_decode(response));
  }

  @override
  Future<List<PlayBundle>> bundles(String packageName, String editId) async {
    final json = await _json(
      'GET',
      _edit(packageName, editId, 'bundles'),
      retryServerErrors: true,
    );
    return [for (final bundle in _objects(json['bundles'])) _bundle(bundle)];
  }

  @override
  Future<PlayTrack> track(
    String packageName,
    String editId,
    String track,
  ) async => _track(
    await _json(
      'GET',
      _edit(packageName, editId, 'tracks/${Uri.encodeComponent(track)}'),
      retryServerErrors: true,
    ),
    track,
  );

  @override
  Future<PlayTrack> updateTrack(
    String packageName,
    String editId,
    PlayTrack track,
  ) async => _track(
    await _json(
      'PUT',
      _edit(packageName, editId, 'tracks/${Uri.encodeComponent(track.name)}'),
      body: {
        'track': track.name,
        'releases': [for (final release in track.releases) _release(release)],
      },
      retryServerErrors: true,
    ),
    track.name,
  );

  @override
  Future<void> commitEdit(String packageName, String editId) async {
    await _send(
      'POST',
      _edit(packageName, '$editId:commit').replace(
        queryParameters: {'changesInReviewBehavior': 'ERROR_IF_IN_REVIEW'},
      ),
    );
  }

  @override
  Future<List<PlayReleaseSummary>> releases(
    String packageName,
    String track,
  ) async {
    final json = await _json(
      'GET',
      _apiBaseUrl.replace(
        path:
            '/androidpublisher/v3/applications/'
            '${Uri.encodeComponent(packageName)}/tracks/'
            '${Uri.encodeComponent(track)}/releases',
      ),
      retryServerErrors: true,
    );
    return [
      for (final summary in _objects(json['releases']))
        PlayReleaseSummary(
          track: _text(summary['track']) ?? track,
          name: _text(summary['releaseName']),
          state: PlayLifecycleState.fromWire(
            _text(summary['releaseLifecycleState']),
          ),
          versionCodes: [
            for (final artifact in _objects(summary['activeArtifacts']))
              ?_int(artifact['versionCode']),
          ],
        ),
    ];
  }

  Uri _edits(String packageName) => _apiBaseUrl.replace(
    path:
        '/androidpublisher/v3/applications/'
        '${Uri.encodeComponent(packageName)}/edits',
  );

  /// The URL of the edit [editId], or of [rest] below it. [editId] may carry a
  /// `:action` suffix.
  Uri _edit(String packageName, String editId, [String? rest]) {
    final colon = editId.indexOf(':');
    final id = colon < 0 ? editId : editId.substring(0, colon);
    final action = colon < 0 ? '' : editId.substring(colon);
    return _apiBaseUrl.replace(
      path:
          '/androidpublisher/v3/applications/'
          '${Uri.encodeComponent(packageName)}/edits/'
          '${Uri.encodeComponent(id)}$action${rest == null ? '' : '/$rest'}',
    );
  }

  Future<Map<String, dynamic>> _json(
    String method,
    Uri url, {
    Map<String, Object?>? body,
    bool retryServerErrors = false,
  }) async => _decode(
    await _send(method, url, body: body, retryServerErrors: retryServerErrors),
  );

  /// Calls the API and returns the successful response.
  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, Object?>? body,
    Stream<List<int>> Function()? content,
    int? length,
    Duration? timeout,
    bool retryServerErrors = false,
  }) async {
    var refreshed = false;
    for (var attempt = 1; ; attempt++) {
      final request = _request(
        method,
        url,
        await _tokens.token(),
        body,
        content,
        length,
      );
      final http.Response response;
      try {
        response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout ?? this.timeout),
        );
      } on TimeoutException {
        throw const PlayServerException(
          0,
          'Google Play did not answer in time.',
        );
      } on http.ClientException catch (error) {
        throw PlayServerException(0, 'Google Play is not reachable: $error');
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
      final wait = retryAfter ?? _backoff(attempt);
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
  ) {
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'User-Agent': 'xpath',
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

  Duration _backoff(int attempt) => Duration(seconds: 1 << (attempt - 1));

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
      throw PlayServerException(
        response.statusCode,
        'Google Play answered with something that is not a JSON object.',
      );
    }
  }

  // Errors.

  PlayException _error(http.Response response, Duration? retryAfter) {
    final (message, reason) = _errorMessage(response);
    final status = response.statusCode;
    if (reason == 'CHANGES_ALREADY_IN_REVIEW') {
      return PlayReviewInProgressException(message, reason: reason);
    }
    if (status >= 400 && status < 500 && _versionCodeUsed(message, reason)) {
      return PlayVersionCodeUsedException(status, message, reason: reason);
    }
    return switch (status) {
      401 => PlayAuthException(message, reason: reason),
      403 => PlayForbiddenException(message, reason: reason),
      404 => PlayNotFoundException(message, reason: reason),
      409 => PlayConflictException(message, reason: reason),
      429 => PlayRateLimitedException(
        message,
        reason: reason,
        retryAfter: retryAfter,
      ),
      >= 500 => PlayServerException(status, message, reason: reason),
      _ => PlayValidationException(status, message, reason: reason),
    };
  }

  bool _versionCodeUsed(String message, String? reason) {
    final text = message.toLowerCase();
    return reason == 'apkUpgradeVersionConflict' ||
        reason == 'bundleVersionConflict' ||
        (text.contains('version code') && text.contains('already been used'));
  }

  /// The message and the reason of a Google error body: `error.message`, and
  /// the `reason` of an `ErrorInfo` in `error.details` or, failing that, of
  /// `error.errors`.
  (String, String?) _errorMessage(http.Response response) {
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>;
      final message = _text(error['message']);
      final reason =
          _objects(error['details'])
              .map((d) => _text(d['reason']))
              .nonNulls
              .firstOrNull ??
          _objects(error['errors'])
              .map((e) => _text(e['reason']))
              .nonNulls
              .firstOrNull;
      return (message ?? 'Google Play refused.', reason);
    } on Object {
      return ('Google Play refused (HTTP ${response.statusCode}).', null);
    }
  }

  // The resources.

  List<Map<String, dynamic>> _objects(Object? value) => [
    if (value is List<dynamic>)
      for (final item in value)
        if (item is Map<String, dynamic>) item,
  ];

  String? _text(Object? value) => value is String ? value : null;

  int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };

  PlayBundle _bundle(Map<String, dynamic> json) {
    final versionCode = _int(json['versionCode']);
    if (versionCode == null) {
      throw const PlayServerException(0, 'Google Play sent no version code.');
    }
    return PlayBundle(versionCode: versionCode, sha256: _text(json['sha256']));
  }

  PlayTrack _track(Map<String, dynamic> json, String name) => PlayTrack(
    name: _text(json['track']) ?? name,
    releases: [
      for (final release in _objects(json['releases']))
        PlayRelease(
          versionCodes: [
            for (final code in release['versionCodes'] as List<dynamic>? ?? [])
              ?_int(code),
          ],
          status: PlayReleaseStatus.fromWire(_text(release['status'])),
          userFraction: (release['userFraction'] as num?)?.toDouble(),
          name: _text(release['name']),
          releaseNotes: {
            for (final note in _objects(release['releaseNotes']))
              ?_text(note['language']): _text(note['text']) ?? '',
          },
        ),
    ],
  );

  Map<String, Object?> _release(PlayRelease release) => {
    'versionCodes': [for (final code in release.versionCodes) '$code'],
    'status': release.status.wire,
    'userFraction': ?release.userFraction,
    'name': ?release.name,
    if (release.releaseNotes.isNotEmpty)
      'releaseNotes': [
        for (final MapEntry(:key, :value) in release.releaseNotes.entries)
          {'language': key, 'text': value},
      ],
  };
}
