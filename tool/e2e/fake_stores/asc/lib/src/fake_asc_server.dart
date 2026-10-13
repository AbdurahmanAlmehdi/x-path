import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_fake_asc/src/fake_asc_key.dart';
import 'package:xp_fake_asc/src/fake_asc_state.dart';
import 'package:xp_fake_asc/src/token_verifier.dart';

/// A fake App Store Connect API and iTunes lookup on a loopback port.
///
/// It serves the endpoints XPath uses (apps, builds, App Store versions,
/// review submissions, phased releases) from state held in memory, in
/// JSON:API shape, and checks the bearer token like Apple does. Tests fill the
/// state with the `add*` methods, make it misbehave with [failNext] and
/// [rateLimitNext], and read what it received from [requests].
class FakeAscServer {
  new _(this._server, this._verifier, this._now, this._quota) {
    _server.listen(_handle);
  }

  /// Starts a server that accepts tokens of [keys] (the test key by default)
  /// and checks their expiry against [now] (the system clock by default).
  /// [hourlyLimit] is the quota reported in `X-Rate-Limit`.
  static Future<FakeAscServer> start({
    Iterable<FakeAscKey> keys = const [fakeAscTestKey],
    DateTime Function()? now,
    int hourlyLimit = 3500,
  }) async {
    final clock = now ?? () => DateTime.now().toUtc();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeAscServer._(
      server,
      AscTokenVerifier(keys: keys, now: clock),
      clock,
      hourlyLimit,
    );
  }

  final HttpServer _server;
  final AscTokenVerifier _verifier;
  final DateTime Function() _now;
  final int _quota;
  var _used = 0;
  var _ids = 0;
  final _failures = <_Failure>[];
  var _rateLimited = 0;
  int? _retryAfter;

  /// The apps, by id.
  final apps = <String, FakeAscApp>{};

  /// The builds.
  final builds = <FakeAscBuild>[];

  /// The App Store versions.
  final versions = <FakeAscVersion>[];

  /// The review submissions, by id.
  final submissions = <String, FakeAscSubmission>{};

  /// The phased releases, by id.
  final phasedReleases = <String, FakeAscPhasedRelease>{};

  /// The iTunes lookup entries, by `bundleId country`.
  final itunes = <String, FakeItunesEntry>{};

  /// Every request received, oldest first.
  final requests = <FakeAscRequest>[];

  /// The address to point the client at.
  Uri get baseUrl => Uri(scheme: 'http', host: 'localhost', port: _server.port);

  /// Stops the server.
  Future<void> close() => _server.close(force: true);

  /// Adds an app.
  FakeAscApp addApp(String bundleId, {String? id, String name = 'App'}) {
    final app = FakeAscApp(
      id: id ?? '${1000000000 + ++_ids}',
      bundleId: bundleId,
      name: name,
    );
    return apps[app.id] = app;
  }

  /// Adds a build of [appId].
  FakeAscBuild addBuild(
    String appId, {
    required String buildNumber,
    required String version,
    String processingState = 'VALID',
    DateTime? uploadedDate,
    bool expired = false,
  }) {
    final build = FakeAscBuild(
      id: 'build-${++_ids}',
      appId: appId,
      buildNumber: buildNumber,
      shortVersion: version,
      processingState: processingState,
      uploadedDate: uploadedDate ?? DateTime.utc(2026, 10, 1, 0, 0, _ids),
      expired: expired,
    );
    builds.add(build);
    return build;
  }

  /// Adds an App Store version of [appId].
  FakeAscVersion addVersion(
    String appId,
    String versionString, {
    String appVersionState = 'PREPARE_FOR_SUBMISSION',
    DateTime? createdDate,
    String platform = 'IOS',
  }) {
    final version = FakeAscVersion(
      id: 'version-${++_ids}',
      appId: appId,
      versionString: versionString,
      appVersionState: appVersionState,
      createdDate: createdDate ?? DateTime.utc(2026, 9, 1, 0, 0, _ids),
      platform: platform,
    );
    versions.add(version);
    return version;
  }

  /// Adds a phased release to the version [versionId].
  FakeAscPhasedRelease addPhasedRelease(
    String versionId, {
    String state = 'INACTIVE',
    int? currentDayNumber,
  }) {
    final release = FakeAscPhasedRelease(
      id: 'phased-${++_ids}',
      versionId: versionId,
      state: state,
      currentDayNumber: currentDayNumber,
    );
    return phasedReleases[release.id] = release;
  }

  /// Makes the iTunes lookup know [bundleId] in the storefront [country].
  void addItunes(
    String bundleId, {
    required String version,
    String country = 'us',
    String? trackId,
  }) => itunes['$bundleId $country'] = FakeItunesEntry(
    bundleId: bundleId,
    trackId: trackId ?? '1000000001',
    version: version,
  );

  /// Makes the next request whose path starts with [pathPrefix] (any request
  /// by default) fail with [status].
  void failNext(
    int status, {
    String code = 'UNEXPECTED_ERROR',
    String title = 'An error occurred.',
    String? detail,
    String pathPrefix = '',
  }) => _failures.add(
    _Failure(pathPrefix, status, code: code, title: title, detail: detail),
  );

  /// Makes the next [count] requests answer 429, with `Retry-After`
  /// [retryAfterSeconds] if given.
  void rateLimitNext(int count, {int? retryAfterSeconds}) {
    _rateLimited = count;
    _retryAfter = retryAfterSeconds;
  }

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final body = text.isEmpty ? null : jsonDecode(text);
    final uri = request.uri;
    final isLookup = uri.path == '/lookup';
    final token = request.headers
        .value(HttpHeaders.authorizationHeader)
        ?.replaceFirst(RegExp('^Bearer '), '');
    final problem = isLookup ? null : _verifier.problem(token);
    requests.add(
      FakeAscRequest(
        method: request.method,
        uri: uri,
        body: body,
        tokenProblem: problem,
      ),
    );

    final response = request.response;
    try {
      if (isLookup) {
        _send(response, 200, _lookup(uri));
        return;
      }
      if (problem != null) {
        throw _AscError(
          401,
          'NOT_AUTHORIZED',
          'Authentication credentials '
              'are missing or invalid.',
          problem,
        );
      }
      if (_rateLimited > 0) {
        _rateLimited--;
        if (_retryAfter != null) {
          response.headers.set(HttpHeaders.retryAfterHeader, '$_retryAfter');
        }
        throw const _AscError(
          429,
          'RATE_LIMIT_EXCEEDED',
          'Rate limit exceeded.',
          'The rate limit for this key was exceeded.',
        );
      }
      final failure = _failures
          .where((failure) => uri.path.startsWith(failure.pathPrefix))
          .firstOrNull;
      if (failure != null) {
        _failures.remove(failure);
        throw _AscError(
          failure.status,
          failure.code,
          failure.title,
          failure.detail,
        );
      }
      _used++;
      response.headers.set(
        'X-Rate-Limit',
        'user-hour-lim:$_quota;user-hour-rem:${_quota - _used};',
      );
      final (status, json) = _route(request.method, uri, body);
      _send(response, status, json);
    } on _AscError catch (error) {
      _send(response, error.status, {
        'errors': [
          {
            'status': '${error.status}',
            'code': error.code,
            'title': error.title,
            'detail': ?error.detail,
          },
        ],
      });
    }
  }

  void _send(HttpResponse response, int status, Object? body) {
    response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'json');
    if (body != null) response.write(jsonEncode(body));
    unawaited(response.close());
  }

  Map<String, Object?> _lookup(Uri uri) {
    final entry =
        itunes['${uri.queryParameters['bundleId']} '
            '${uri.queryParameters['country']}'];
    return {
      'resultCount': entry == null ? 0 : 1,
      'results': [
        if (entry != null)
          {
            'bundleId': entry.bundleId,
            'trackId': int.parse(entry.trackId),
            'version': entry.version,
            'currentVersionReleaseDate': entry.releaseDate,
          },
      ],
    };
  }

  (int, Object?) _route(String method, Uri uri, Object? body) {
    final path = uri.pathSegments;
    if (path.length < 2 || path.first != 'v1') throw _notFound(uri);
    final rest = path.sublist(1);
    final query = uri.queryParameters;
    switch ((method, rest)) {
      case ('GET', ['apps']):
        final bundleId = query['filter[bundleId]'];
        return _ok(uri, [
          for (final app in apps.values)
            if (bundleId == null || app.bundleId == bundleId) _app(app),
        ]);
      case ('GET', ['builds']):
        return _builds(uri);
      case ('GET', ['apps', final id, 'appStoreVersions']):
        _app404(id);
        final platform = query['filter[platform]'];
        final matching = [
          for (final version in versions)
            if (version.appId == id &&
                (platform == null || version.platform == platform))
              version,
        ]..sort((a, b) => b.createdDate.compareTo(a.createdDate));
        return _ok(uri, [for (final version in matching) _version(version)]);
      case ('GET', ['apps', final id, 'reviewSubmissions']):
        _app404(id);
        final matching = [
          for (final submission in submissions.values.toList().reversed)
            if (submission.appId == id) _submission(submission),
        ];
        return _ok(uri, matching);
      case ('POST', ['reviewSubmissions']):
        return _createSubmission(body);
      case ('GET', ['reviewSubmissions', final id]):
        return (200, {'data': _submission(_submission404(id))});
      case ('PATCH', ['reviewSubmissions', final id]):
        return _submit(id, body);
      case ('POST', ['reviewSubmissionItems']):
        return _addItem(body);
      case (
        'GET',
        ['appStoreVersions', final id, 'appStoreVersionPhasedRelease'],
      ):
        if (versions.every((version) => version.id != id)) {
          throw _AscError(404, 'NOT_FOUND', 'Not found.', 'No version $id.');
        }
        final release = phasedReleases.values
            .where((release) => release.versionId == id)
            .firstOrNull;
        if (release == null) {
          throw const _AscError(
            404,
            'NOT_FOUND',
            'The specified resource does not exist.',
            'The version has no phased release.',
          );
        }
        return (200, {'data': _phased(release)});
      case ('PATCH', ['appStoreVersionPhasedReleases', final id]):
        return _updatePhased(id, body);
    }
    throw _notFound(uri);
  }

  (int, Object?) _ok(
    Uri uri,
    List<Map<String, Object?>> data, {
    List<Object?>? included,
  }) {
    final query = uri.queryParameters;
    final limit = (int.tryParse(query['limit'] ?? '') ?? 50).clamp(1, 200);
    final start = int.tryParse(query['cursor'] ?? '') ?? 0;
    final end = (start + limit).clamp(0, data.length);
    final next = end < data.length
        ? uri.replace(
            scheme: baseUrl.scheme,
            host: baseUrl.host,
            port: baseUrl.port,
            queryParameters: {...query, 'cursor': '$end'},
          )
        : null;
    return (
      200,
      {
        'data': data.sublist(start.clamp(0, data.length), end),
        'included': ?included,
        'links': {'self': '$uri', 'next': ?next?.toString()},
        'meta': {
          'paging': {'total': data.length, 'limit': limit},
        },
      },
    );
  }

  (int, Object?) _builds(Uri uri) {
    final query = uri.queryParameters;
    final matching = [
      for (final build in builds)
        if ((query['filter[app]'] == null ||
                build.appId == query['filter[app]']) &&
            (query['filter[version]'] == null ||
                build.buildNumber == query['filter[version]']) &&
            (query['filter[preReleaseVersion.version]'] == null ||
                build.shortVersion ==
                    query['filter[preReleaseVersion.version]']) &&
            (query['filter[processingState]'] == null ||
                build.processingState == query['filter[processingState]']))
          build,
    ]..sort((a, b) => b.uploadedDate.compareTo(a.uploadedDate));
    final withTrain = (query['include'] ?? '').contains('preReleaseVersion');
    return _ok(
      uri,
      [for (final build in matching) _build(build)],
      included: withTrain
          ? [
              for (final train in {
                for (final build in matching)
                  _trainId(build): build.shortVersion,
              }.entries)
                {
                  'type': 'preReleaseVersions',
                  'id': train.key,
                  'attributes': {'version': train.value, 'platform': 'IOS'},
                },
            ]
          : null,
    );
  }

  (int, Object?) _createSubmission(Object? body) {
    final data = _data(body);
    final appId = _relationship(data, 'app');
    _app404(appId);
    final submission = FakeAscSubmission(
      id: 'submission-${++_ids}',
      appId: appId,
      platform:
          (data['attributes'] as Map<String, dynamic>?)?['platform']
              as String? ??
          'IOS',
    );
    submissions[submission.id] = submission;
    return (201, {'data': _submission(submission)});
  }

  (int, Object?) _addItem(Object? body) {
    final data = _data(body);
    final submission = _submission404(_relationship(data, 'reviewSubmission'));
    final versionId = _relationship(data, 'appStoreVersion');
    if (versions.every((version) => version.id != versionId)) {
      throw _AscError(404, 'NOT_FOUND', 'Not found.', 'No version $versionId.');
    }
    submission.versionIds.add(versionId);
    return (
      201,
      {
        'data': {'type': 'reviewSubmissionItems', 'id': 'item-${++_ids}'},
      },
    );
  }

  (int, Object?) _submit(String id, Object? body) {
    final submission = _submission404(id);
    final attributes = _data(body)['attributes'] as Map<String, dynamic>?;
    if (attributes?['submitted'] == true) {
      if (submission.versionIds.isEmpty) {
        throw const _AscError(
          409,
          'ENTITY_ERROR',
          'The submission has no items.',
          'Add the app store version to the submission first.',
        );
      }
      submission
        ..state = 'WAITING_FOR_REVIEW'
        ..submittedDate = _now();
      for (final version in versions) {
        if (submission.versionIds.contains(version.id)) {
          version.appVersionState = 'WAITING_FOR_REVIEW';
        }
      }
    }
    return (200, {'data': _submission(submission)});
  }

  (int, Object?) _updatePhased(String id, Object? body) {
    final release = phasedReleases[id];
    if (release == null) {
      throw _AscError(404, 'NOT_FOUND', 'Not found.', 'No phased release $id.');
    }
    final state =
        (_data(body)['attributes']
            as Map<String, dynamic>?)?['phasedReleaseState'];
    if (!const {'INACTIVE', 'ACTIVE', 'PAUSED', 'COMPLETE'}.contains(state)) {
      throw _AscError(
        422,
        'ENTITY_ERROR.ATTRIBUTE.INVALID',
        'An attribute value is invalid.',
        'phasedReleaseState $state is not valid.',
      );
    }
    release.state = state! as String;
    return (200, {'data': _phased(release)});
  }

  Map<String, dynamic> _data(Object? body) {
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) {
      throw const _AscError(
        400,
        'PARAMETER_ERROR.INVALID',
        'The request body is invalid.',
        'There is no data object.',
      );
    }
    return data;
  }

  String _relationship(Map<String, dynamic> data, String name) {
    final relationships = data['relationships'] as Map<String, dynamic>?;
    final related = (relationships?[name] as Map<String, dynamic>?)?['data'];
    final id = related is Map<String, dynamic> ? related['id'] : null;
    if (id is! String) {
      throw _AscError(
        409,
        'ENTITY_ERROR.RELATIONSHIP.REQUIRED',
        'A required relationship is missing.',
        'The relationship $name is required.',
      );
    }
    return id;
  }

  void _app404(String id) {
    if (!apps.containsKey(id)) {
      throw _AscError(404, 'NOT_FOUND', 'Not found.', 'No app $id.');
    }
  }

  FakeAscSubmission _submission404(String id) =>
      submissions[id] ??
      (throw _AscError(404, 'NOT_FOUND', 'Not found.', 'No submission $id.'));

  _AscError _notFound(Uri uri) => _AscError(
    404,
    'NOT_FOUND',
    'The specified resource does not exist.',
    'There is nothing at ${uri.path}.',
  );

  String _trainId(FakeAscBuild build) =>
      'train-${build.appId}-${build.shortVersion}';

  Map<String, Object?> _app(FakeAscApp app) => {
    'type': 'apps',
    'id': app.id,
    'attributes': {'name': app.name, 'bundleId': app.bundleId},
  };

  Map<String, Object?> _build(FakeAscBuild build) => {
    'type': 'builds',
    'id': build.id,
    'attributes': {
      'version': build.buildNumber,
      'uploadedDate': build.uploadedDate.toIso8601String(),
      'processingState': build.processingState,
      'expired': build.expired,
    },
    'relationships': {
      'preReleaseVersion': {
        'data': {'type': 'preReleaseVersions', 'id': _trainId(build)},
      },
    },
  };

  Map<String, Object?> _version(FakeAscVersion version) => {
    'type': 'appStoreVersions',
    'id': version.id,
    'attributes': {
      'platform': version.platform,
      'versionString': version.versionString,
      // The deprecated field comes with a value of its own, to prove that the
      // client reads appVersionState.
      'appStoreState': 'LEGACY_${version.appVersionState}',
      'appVersionState': version.appVersionState,
      'createdDate': version.createdDate.toIso8601String(),
    },
  };

  Map<String, Object?> _submission(FakeAscSubmission submission) => {
    'type': 'reviewSubmissions',
    'id': submission.id,
    'attributes': {
      'platform': submission.platform,
      'state': submission.state,
      'submittedDate': submission.submittedDate?.toIso8601String(),
    },
  };

  Map<String, Object?> _phased(FakeAscPhasedRelease release) => {
    'type': 'appStoreVersionPhasedReleases',
    'id': release.id,
    'attributes': {
      'phasedReleaseState': release.state,
      'currentDayNumber': release.currentDayNumber,
    },
  };
}

class _Failure {
  const new(
    this.pathPrefix,
    this.status, {
    required this.code,
    required this.title,
    required this.detail,
  });

  final String pathPrefix;
  final int status;
  final String code;
  final String title;
  final String? detail;
}

class _AscError implements Exception {
  const new(this.status, this.code, this.title, [this.detail]);

  final int status;
  final String code;
  final String title;
  final String? detail;
}
