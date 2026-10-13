import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_adapters/src/stores/apple/asc_token_provider.dart';
import 'package:xp_engine/xp_engine.dart';

/// An [AppStoreConnect] over the App Store Connect REST API.
///
/// Every call carries a bearer token from an [AscTokenProvider]. The token is
/// sent only to the host of the base URL, so a `links.next` that points
/// elsewhere is refused. Lists follow `links.next` page by page.
///
/// Rate limiting: a `429` is waited out if Apple says to wait no longer than
/// [maxWait] (`Retry-After`, else exponential backoff) and retried up to
/// [maxAttempts] times; a longer wait (the hourly quota is spent) ends in an
/// [AscRateLimitedException] with the time to wait, because a job must not
/// sleep for an hour. A `5xx` on a read is retried the same way. The quota that
/// is left comes from the `X-Rate-Limit` header of each answer ([rateLimit]).
class HttpAppStoreConnect implements AppStoreConnect {
  /// Creates a client for the API key [key].
  ///
  /// The base URL is `https://api.appstoreconnect.apple.com` unless a test
  /// says otherwise; [client] and [sleep] are for tests.
  new({
    required AscKey key,
    required Clock clock,
    http.Client? client,
    Uri? baseUrl,
    this.maxAttempts = 3,
    this.maxWait = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 60),
    Future<void> Function(Duration)? sleep,
  }) : _tokens = AscTokenProvider(key: key, clock: clock),
       _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? Uri.parse('https://api.appstoreconnect.apple.com'),
       _sleep = sleep ?? Future.delayed;

  static const _maxPages = 50;

  /// How many times a call is made before a `429` or a `5xx` is given up on.
  final int maxAttempts;

  /// The longest the client waits between two attempts.
  final Duration maxWait;

  /// How long one request has to be answered.
  final Duration timeout;

  final AscTokenProvider _tokens;
  final http.Client _client;
  final Uri _baseUrl;
  final Future<void> Function(Duration) _sleep;

  @override
  AscRateLimit? rateLimit;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  Future<AscApp?> findApp(String bundleId) async {
    final documents = await _list('/v1/apps', {
      'filter[bundleId]': bundleId,
      'limit': '10',
    });
    for (final resource in documents.data) {
      final app = _app(resource);
      if (app.bundleId == bundleId) return app;
    }
    return null;
  }

  @override
  Future<List<AscBuild>> builds(
    String appId, {
    String? version,
    String? buildNumber,
  }) async {
    final documents = await _list('/v1/builds', {
      'filter[app]': appId,
      'filter[preReleaseVersion.version]': ?version,
      'filter[version]': ?buildNumber,
      'include': 'preReleaseVersion',
      'sort': '-uploadedDate',
    });
    final trains = {
      for (final resource in documents.included)
        if (resource['type'] == 'preReleaseVersions')
          resource['id'] as String: _string(_attributes(resource), 'version'),
    };
    return [for (final resource in documents.data) _build(resource, trains)];
  }

  @override
  Future<List<AscAppStoreVersion>> versions(String appId) async {
    final documents = await _list('/v1/apps/$appId/appStoreVersions', {
      'filter[platform]': 'IOS',
    });
    return [for (final resource in documents.data) _version(resource)]
      ..sort((a, b) => _byDate(b.createdDate, a.createdDate));
  }

  @override
  Future<List<AscReviewSubmission>> reviewSubmissions(String appId) async {
    final documents = await _list('/v1/apps/$appId/reviewSubmissions', {
      'filter[platform]': 'IOS',
    });
    return [for (final resource in documents.data) _submission(resource)];
  }

  @override
  Future<AscReviewSubmission> reviewSubmission(String id) async =>
      _submission(_one(await _send('GET', _url('/v1/reviewSubmissions/$id'))));

  @override
  Future<AscReviewSubmission> createReviewSubmission(
    String appId,
    String versionId,
  ) async {
    final created = _submission(
      _one(
        await _send(
          'POST',
          _url('/v1/reviewSubmissions'),
          body: {
            'data': {
              'type': 'reviewSubmissions',
              'attributes': {'platform': 'IOS'},
              'relationships': {'app': _link('apps', appId)},
            },
          },
        ),
      ),
    );
    await _send(
      'POST',
      _url('/v1/reviewSubmissionItems'),
      body: {
        'data': {
          'type': 'reviewSubmissionItems',
          'relationships': {
            'reviewSubmission': _link('reviewSubmissions', created.id),
            'appStoreVersion': _link('appStoreVersions', versionId),
          },
        },
      },
    );
    return created;
  }

  @override
  Future<AscReviewSubmission> submitReviewSubmission(String id) async =>
      _submission(
        _one(
          await _send(
            'PATCH',
            _url('/v1/reviewSubmissions/$id'),
            body: {
              'data': {
                'type': 'reviewSubmissions',
                'id': id,
                'attributes': {'submitted': true},
              },
            },
          ),
        ),
      );

  @override
  Future<AscPhasedRelease?> phasedRelease(String versionId) async {
    try {
      return _phased(
        _one(
          await _send(
            'GET',
            _url(
              '/v1/appStoreVersions/$versionId/appStoreVersionPhasedRelease',
            ),
          ),
        ),
      );
    } on AscNotFoundException {
      return null;
    }
  }

  @override
  Future<AscPhasedRelease> updatePhasedRelease(
    String id,
    PhasedReleaseState state,
  ) async => _phased(
    _one(
      await _send(
        'PATCH',
        _url('/v1/appStoreVersionPhasedReleases/$id'),
        body: {
          'data': {
            'type': 'appStoreVersionPhasedReleases',
            'id': id,
            'attributes': {'phasedReleaseState': state.wire},
          },
        },
      ),
    ),
  );

  Uri _url(String path, [Map<String, String>? query]) => _baseUrl.replace(
    path: path,
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  /// Reads every page of the list at [path].
  Future<
    ({List<Map<String, dynamic>> data, List<Map<String, dynamic>> included})
  >
  _list(String path, Map<String, String> query) async {
    final data = <Map<String, dynamic>>[];
    final included = <Map<String, dynamic>>[];
    var url = _url(path, {'limit': '200', ...query});
    for (var page = 0; page < _maxPages; page++) {
      final document = await _send('GET', url);
      data.addAll(_resources(document['data']));
      included.addAll(_resources(document['included']));
      final links = document['links'];
      final next = links is Map<String, dynamic> ? links['next'] : null;
      if (next is! String) return (data: data, included: included);
      url = Uri.parse(next);
      if (url.scheme != _baseUrl.scheme ||
          url.host != _baseUrl.host ||
          url.port != _baseUrl.port) {
        throw AscServerException(
          0,
          'App Store Connect paged to another host, ${url.host}; the token '
          'is not sent there.',
        );
      }
    }
    throw const AscServerException(0, 'App Store Connect paged without end.');
  }

  /// Calls the API and decodes the JSON object it answers with.
  Future<Map<String, dynamic>> _send(
    String method,
    Uri url, {
    Map<String, Object?>? body,
  }) async {
    for (var attempt = 1; ; attempt++) {
      final request = http.Request(method, url)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/json',
          'Authorization': 'Bearer ${_token()}',
          'User-Agent': 'xpath',
          if (body != null) 'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final http.Response response;
      try {
        response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout),
        );
      } on TimeoutException {
        throw const AscServerException(
          0,
          'App Store Connect did not answer in time.',
        );
      } on http.ClientException catch (error) {
        throw AscServerException(
          0,
          'App Store Connect is not reachable: $error',
        );
      }
      rateLimit =
          AscRateLimit.parse(response.headers['x-rate-limit']) ?? rateLimit;
      final status = response.statusCode;
      if (status >= 200 && status < 300) return _decode(response);

      final retryAfter = _retryAfter(response);
      final wait = retryAfter ?? _backoff(attempt);
      final retryable = status == 429 || (status >= 500 && method == 'GET');
      if (retryable && attempt < maxAttempts && wait <= maxWait) {
        await _sleep(wait);
        continue;
      }
      throw _error(response, retryAfter);
    }
  }

  String _token() {
    try {
      return _tokens.token();
    } on FormatException catch (error) {
      throw AscAuthException(
        'The ASC private key cannot be used: ${error.message}',
      );
    }
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
      throw AscServerException(
        response.statusCode,
        'App Store Connect answered with something that is not a JSON object.',
      );
    }
  }

  AppStoreConnectException _error(
    http.Response response,
    Duration? retryAfter,
  ) {
    final (message, code) = _errorMessage(response);
    return switch (response.statusCode) {
      401 => AscAuthException(message, code: code),
      403 => AscForbiddenException(message, code: code),
      404 => AscNotFoundException(message, code: code),
      409 => AscConflictException(message, code: code),
      422 => AscValidationException(message, code: code),
      429 => AscRateLimitedException(
        message,
        code: code,
        retryAfter: retryAfter,
      ),
      final status => AscServerException(status, message, code: code),
    };
  }

  (String, String?) _errorMessage(http.Response response) {
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final errors = [
        for (final error in json['errors'] as List<dynamic>? ?? const [])
          if (error is Map<String, dynamic>) error,
      ];
      final messages = [
        for (final error in errors)
          if (error['detail'] ?? error['title'] case final String text) text,
      ];
      return (
        messages.isEmpty ? 'App Store Connect refused.' : messages.join('; '),
        errors.firstOrNull?['code'] as String?,
      );
    } on Object {
      return ('App Store Connect refused (HTTP ${response.statusCode}).', null);
    }
  }

  // JSON:API documents.

  Map<String, dynamic> _one(Map<String, dynamic> document) {
    final data = document['data'];
    if (data is Map<String, dynamic>) return data;
    throw const AscServerException(0, 'App Store Connect sent no resource.');
  }

  List<Map<String, dynamic>> _resources(Object? value) => [
    if (value is List<dynamic>)
      for (final item in value)
        if (item is Map<String, dynamic>) item,
  ];

  Map<String, dynamic> _attributes(Map<String, dynamic> resource) {
    final attributes = resource['attributes'];
    return attributes is Map<String, dynamic> ? attributes : const {};
  }

  String _string(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is String) return value;
    throw AscServerException(0, 'App Store Connect sent no "$field".');
  }

  String? _optional(Map<String, dynamic> map, String field) {
    final value = map[field];
    return value is String ? value : null;
  }

  DateTime? _date(Map<String, dynamic> map, String field) {
    final text = _optional(map, field);
    return text == null ? null : DateTime.tryParse(text)?.toUtc();
  }

  int _byDate(DateTime? a, DateTime? b) =>
      a == null || b == null ? 0 : a.compareTo(b);

  Map<String, Object?> _link(String type, String id) => {
    'data': {'type': type, 'id': id},
  };

  AscApp _app(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    return AscApp(
      id: _string(resource, 'id'),
      bundleId: _string(attributes, 'bundleId'),
      name: _optional(attributes, 'name'),
    );
  }

  AscBuild _build(Map<String, dynamic> resource, Map<String, String> trains) {
    final attributes = _attributes(resource);
    final relationship = resource['relationships'];
    final train = relationship is Map<String, dynamic>
        ? relationship['preReleaseVersion']
        : null;
    final trainData = train is Map<String, dynamic> ? train['data'] : null;
    return AscBuild(
      id: _string(resource, 'id'),
      buildNumber: _string(attributes, 'version'),
      version: trainData is Map<String, dynamic>
          ? trains[trainData['id']]
          : null,
      processingState: AscProcessingState.fromWire(
        _optional(attributes, 'processingState'),
      ),
      uploadedDate: _date(attributes, 'uploadedDate'),
      expired: attributes['expired'] == true,
    );
  }

  /// Reads `appVersionState` only: `appStoreState` is deprecated (API 3.7).
  AscAppStoreVersion _version(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    return AscAppStoreVersion(
      id: _string(resource, 'id'),
      versionString: _string(attributes, 'versionString'),
      platform: _optional(attributes, 'platform') ?? 'IOS',
      state: AppVersionState.fromWire(_optional(attributes, 'appVersionState')),
      createdDate: _date(attributes, 'createdDate'),
    );
  }

  AscReviewSubmission _submission(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    return AscReviewSubmission(
      id: _string(resource, 'id'),
      state: ReviewSubmissionState.fromWire(_optional(attributes, 'state')),
      platform: _optional(attributes, 'platform') ?? 'IOS',
      submittedDate: _date(attributes, 'submittedDate'),
    );
  }

  AscPhasedRelease _phased(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    final state = PhasedReleaseState.fromWire(
      _optional(attributes, 'phasedReleaseState'),
    );
    if (state == null) {
      throw const AscServerException(
        0,
        'App Store Connect sent an unknown phased release state.',
      );
    }
    final day = attributes['currentDayNumber'];
    return AscPhasedRelease(
      id: _string(resource, 'id'),
      state: state,
      currentDayNumber: day is int ? day : null,
    );
  }
}
