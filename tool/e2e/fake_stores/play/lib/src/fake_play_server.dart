import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:xp_fake_play/src/assertion_verifier.dart';
import 'package:xp_fake_play/src/fake_play_account.dart';
import 'package:xp_fake_play/src/fake_play_state.dart';

/// The bytes of a bundle the fake server accepts: it reads the version code
/// from the first line, where Google Play reads the manifest.
List<int> fakeAab(int versionCode, {int padding = 0}) =>
    utf8.encode('fake-aab versionCode=$versionCode\n${'x' * padding}');

const _inReview = 'RELEASE_LIFECYCLE_STATE_IN_REVIEW';

/// A fake Google Play Developer API and OAuth2 token endpoint on a loopback
/// port.
///
/// It serves the calls XPath makes (`edits.insert`, `edits.delete`,
/// `edits.bundles.upload` and `list`, `edits.tracks.get` and `update`,
/// `edits.commit`, `tracks.releases.list`) from state held in memory, in
/// Google's JSON, and the JWT bearer flow at `/token`. It checks the signed
/// assertion like Google does and the access token on every API call.
///
/// A commit while changes are in review behaves like the real thing: with
/// `changesInReviewBehavior=ERROR_IF_IN_REVIEW` it answers `400
/// FAILED_PRECONDITION` (`CHANGES_ALREADY_IN_REVIEW`), leaves the edit valid
/// and the review alone; without the parameter it cancels the review. The
/// server records both ([commits], [FakePlayApp.cancelledReviews]), so a test
/// can assert that a review survived and the parameter was sent.
class FakePlayServer {
  new _(
    this._server,
    this._now,
    this._accounts,
    this._lifetime,
    this._editLifetime,
  ) {
    _verifier = AssertionVerifier(
      accounts: _accounts,
      audience: tokenUri.toString(),
      now: _now,
    );
    _server.listen(_handle);
  }

  /// Starts a server that accepts assertions of [accounts] (the test account
  /// by default) and checks their expiry against [now] (the system clock by
  /// default). Access tokens live [tokenLifetime]; edits [editLifetime].
  static Future<FakePlayServer> start({
    Iterable<FakePlayAccount> accounts = const [fakePlayTestAccount],
    DateTime Function()? now,
    Duration tokenLifetime = const Duration(hours: 1),
    Duration editLifetime = const Duration(hours: 24),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakePlayServer._(
      server,
      now ?? () => DateTime.now().toUtc(),
      accounts.toList(),
      tokenLifetime,
      editLifetime,
    );
  }

  final HttpServer _server;
  final DateTime Function() _now;
  final List<FakePlayAccount> _accounts;
  final Duration _lifetime;
  final Duration _editLifetime;
  late final AssertionVerifier _verifier;
  var _ids = 0;
  final _tokens = <String, DateTime>{};
  final _failures = <_Failure>[];
  var _rateLimited = 0;
  int? _retryAfter;

  /// The apps, by application id.
  final apps = <String, FakePlayApp>{};

  /// The edits, by id.
  final edits = <String, FakePlayEdit>{};

  /// Every request received, oldest first.
  final requests = <FakePlayRequest>[];

  /// Every commit received, oldest first.
  final commits = <FakePlayCommit>[];

  /// The access tokens issued so far.
  int tokensIssued = 0;

  /// When set, every bundle upload reports this version code, whatever the
  /// bytes say: the fake cannot read the manifest of a real Android App
  /// Bundle, which an end-to-end run uploads. The bytes may be anything.
  int? uploadVersionCode;

  /// Whether releases that a commit makes go to review (`IN_REVIEW`) instead
  /// of straight to `PUBLISHED`.
  bool sendsToReview = false;

  /// The address to point the client at.
  Uri get baseUrl => Uri(scheme: 'http', host: 'localhost', port: _server.port);

  /// The token endpoint, the `token_uri` of a service account file.
  Uri get tokenUri => baseUrl.replace(path: '/token');

  /// Stops the server.
  Future<void> close() => _server.close(force: true);

  /// The JSON of a service account key file for the test account, pointing at
  /// this server's token endpoint. Pass another [privateKeyPem] to get a key
  /// the server does not know.
  String serviceAccountJson({
    String clientEmail = fakePlayClientEmail,
    String privateKeyPem = fakePlayPrivateKeyPem,
  }) => jsonEncode({
    'type': 'service_account',
    'project_id': 'xpath-test',
    'private_key_id': fakePlayPrivateKeyId,
    'private_key': privateKeyPem,
    'client_email': clientEmail,
    'token_uri': tokenUri.toString(),
  });

  /// Adds an app.
  FakePlayApp addApp(String packageName, {Set<String>? allowedAccounts}) =>
      apps[packageName] = FakePlayApp(
        packageName,
        allowedAccounts: allowedAccounts,
      );

  /// Forgets every access token, so that the next API call is refused.
  void revokeTokens() => _tokens.clear();

  /// Makes the next request whose path contains [pathContains] (any request
  /// by default) and whose method is [method] (any by default) fail with
  /// [status].
  void failNext(
    int status, {
    String message = 'An error occurred.',
    String? reason,
    String pathContains = '',
    String? method,
  }) => _failures.add(
    _Failure(
      status,
      message: message,
      reason: reason,
      pathContains: pathContains,
      method: method,
    ),
  );

  /// Makes the next [count] API requests answer 429, with `Retry-After`
  /// [retryAfterSeconds] if given.
  void rateLimitNext(int count, {int? retryAfterSeconds}) {
    _rateLimited = count;
    _retryAfter = retryAfterSeconds;
  }

  Future<void> _handle(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await request.forEach(builder.add);
    final bytes = builder.takeBytes();
    final uri = request.uri;
    final contentType = request.headers.contentType?.mimeType;
    final isToken = uri.path == '/token';
    Object? json;
    if (contentType == 'application/json' && bytes.isNotEmpty) {
      json = jsonDecode(utf8.decode(bytes));
    }
    final token = request.headers
        .value(HttpHeaders.authorizationHeader)
        ?.replaceFirst(RegExp('^Bearer '), '');
    final tokenProblem = isToken ? null : _tokenProblem(token);
    requests.add(
      FakePlayRequest(
        method: request.method,
        uri: uri,
        body: json,
        bodyLength: bytes.length,
        contentType: contentType,
        tokenProblem: tokenProblem,
      ),
    );

    final response = request.response;
    try {
      if (isToken) {
        _send(response, 200, _issue(utf8.decode(bytes)));
        return;
      }
      if (tokenProblem != null) {
        throw _PlayError(401, tokenProblem, 'UNAUTHENTICATED');
      }
      if (_rateLimited > 0) {
        _rateLimited--;
        if (_retryAfter != null) {
          response.headers.set(HttpHeaders.retryAfterHeader, '$_retryAfter');
        }
        throw const _PlayError(
          429,
          'Quota exceeded for quota metric.',
          'RESOURCE_EXHAUSTED',
          reason: 'rateLimitExceeded',
        );
      }
      final failure = _failures
          .where(
            (failure) =>
                uri.path.contains(failure.pathContains) &&
                (failure.method == null || failure.method == request.method),
          )
          .firstOrNull;
      if (failure != null) {
        _failures.remove(failure);
        throw _PlayError(
          failure.status,
          failure.message,
          _statusName(failure.status),
          reason: failure.reason,
        );
      }
      final email = _emailOf(token!);
      final (status, body) = _route(request.method, uri, json, bytes, email);
      _send(response, status, body);
    } on _PlayError catch (error) {
      _send(response, error.status, error.toJson());
    } on _TokenError catch (error) {
      _send(response, 400, {
        'error': error.error,
        'error_description': error.description,
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

  // The token endpoint.

  Map<String, Object?> _issue(String form) {
    final fields = Uri.splitQueryString(form);
    if (fields['grant_type'] != 'urn:ietf:params:oauth:grant-type:jwt-bearer') {
      throw const _TokenError('unsupported_grant_type', 'Invalid grant_type.');
    }
    final problem = _verifier.problem(fields['assertion']);
    if (problem != null) {
      throw _TokenError(problem.error, problem.description);
    }
    final claims = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(fields['assertion']!.split('.')[1]),
        ),
      ),
    ) as Map<String, dynamic>;
    final token = 'ya29.fake-${++tokensIssued}-${claims['iss']}';
    _tokens[token] = _now().add(_lifetime);
    return {
      'access_token': token,
      'expires_in': _lifetime.inSeconds,
      'token_type': 'Bearer',
    };
  }

  String? _tokenProblem(String? token) {
    if (token == null) return 'Request is missing required authentication.';
    final expires = _tokens[token];
    if (expires == null) return 'The access token is not valid.';
    if (!_now().isBefore(expires)) return 'The access token has expired.';
    return null;
  }

  String _emailOf(String token) => token.split('-').skip(2).join('-');

  // The API.

  (int, Object?) _route(
    String method,
    Uri uri,
    Object? json,
    List<int> bytes,
    String email,
  ) {
    final path = uri.pathSegments;
    final isUpload = path.firstOrNull == 'upload';
    final api = isUpload ? path.sublist(1) : path;
    if (api.length < 4 ||
        api[0] != 'androidpublisher' ||
        api[1] != 'v3' ||
        api[2] != 'applications') {
      throw _notFound('No such method: ${uri.path}.');
    }
    final app = _app(api[3], email);
    final rest = api.sublist(4);
    switch ((method, rest)) {
      case ('POST', ['edits']):
        return _insertEdit(app);
      case ('DELETE', ['edits', final id]):
        _edit(app, id).deleted = true;
        return (204, null);
      case ('POST', ['edits', final idAndAction])
          when idAndAction.contains(':'):
        final [id, action] = idAndAction.split(':');
        return switch (action) {
          'commit' => _commit(app, _edit(app, id), uri),
          _ => throw _notFound('No such action: $action.'),
        };
      case ('POST', ['edits', final id, 'bundles']) when isUpload:
        return _upload(app, _edit(app, id), uri, bytes);
      case ('GET', ['edits', final id, 'bundles']):
        final edit = _edit(app, id);
        return (
          200,
          {
            'kind': 'androidpublisher#bundlesListResponse',
            'bundles': [
              for (final bundle in {...app.bundles, ...edit.bundles}.values)
                bundle.toJson(),
            ],
          },
        );
      case ('GET', ['edits', final id, 'tracks', final track]):
        return (200, _trackJson(app, _edit(app, id), track));
      case ('PUT', ['edits', final id, 'tracks', final track]):
        return _updateTrack(app, _edit(app, id), track, json);
      case ('GET', ['tracks', final track, 'releases']):
        return (200, _releaseList(app, track));
      default:
        throw _notFound('No such method: $method ${uri.path}.');
    }
  }

  FakePlayApp _app(String packageName, String email) {
    final app = apps[packageName];
    if (app == null) {
      throw _notFound(
        'Package not found: $packageName.',
        reason: 'applicationNotFound',
      );
    }
    final allowed = app.allowedAccounts;
    if (allowed != null && !allowed.contains(email)) {
      throw const _PlayError(
        403,
        'The caller does not have permission',
        'PERMISSION_DENIED',
        reason: 'forbidden',
      );
    }
    return app;
  }

  FakePlayEdit _edit(FakePlayApp app, String id) {
    final edit = edits[id];
    if (edit == null ||
        edit.packageName != app.packageName ||
        edit.deleted ||
        edit.committed ||
        !_now().isBefore(edit.expiresAt)) {
      throw _notFound('Edit not found: $id.', reason: 'editNotFound');
    }
    return edit;
  }

  (int, Object?) _insertEdit(FakePlayApp app) {
    final edit = FakePlayEdit(
      id: 'edit-${++_ids}',
      packageName: app.packageName,
      expiresAt: _now().add(_editLifetime),
    );
    edits[edit.id] = edit;
    return (
      200,
      {
        'id': edit.id,
        'expiryTimeSeconds': '${edit.expiresAt.millisecondsSinceEpoch ~/ 1000}',
      },
    );
  }

  int _versionCodeOf(List<int> bytes) {
    final text = utf8.decode(bytes.take(80).toList(), allowMalformed: true);
    final match = RegExp(r'^fake-aab versionCode=(\d+)\n').firstMatch(text);
    if (match == null) {
      throw const _PlayError(
        400,
        'The uploaded file is not a valid Android App Bundle.',
        'INVALID_ARGUMENT',
      );
    }
    return int.parse(match[1]!);
  }

  (int, Object?) _upload(
    FakePlayApp app,
    FakePlayEdit edit,
    Uri uri,
    List<int> bytes,
  ) {
    if (uri.queryParameters['uploadType'] != 'media') {
      throw const _PlayError(
        400,
        'This fake only takes uploadType=media.',
        'INVALID_ARGUMENT',
      );
    }
    final versionCode = uploadVersionCode ?? _versionCodeOf(bytes);
    if (app.bundles.containsKey(versionCode) ||
        edit.bundles.containsKey(versionCode)) {
      throw _PlayError(
        403,
        'Version code $versionCode has already been used.',
        'PERMISSION_DENIED',
        reason: 'apkUpgradeVersionConflict',
      );
    }
    final data = Uint8List.fromList(bytes);
    final bundle = FakePlayBundle(
      versionCode: versionCode,
      sha1: _hex(SHA1Digest().process(data)),
      sha256: _hex(SHA256Digest().process(data)),
    );
    edit.bundles[versionCode] = bundle;
    return (200, bundle.toJson());
  }

  Map<String, Object?> _trackJson(
    FakePlayApp app,
    FakePlayEdit edit,
    String track,
  ) {
    final releases = edit.tracks[track] ?? app.tracks[track] ?? const [];
    return {
      'track': track,
      'releases': [for (final release in releases) release.toTrackRelease()],
    };
  }

  (int, Object?) _updateTrack(
    FakePlayApp app,
    FakePlayEdit edit,
    String track,
    Object? json,
  ) {
    if (json is! Map<String, dynamic>) {
      throw const _PlayError(400, 'Invalid JSON payload.', 'INVALID_ARGUMENT');
    }
    if (json['track'] != null && json['track'] != track) {
      throw const _PlayError(
        400,
        'The track in the body must be the track in the path.',
        'INVALID_ARGUMENT',
      );
    }
    final releases = <FakePlayRelease>[];
    for (final item in json['releases'] as List<dynamic>? ?? const []) {
      releases.add(_release(app, edit, item as Map<String, dynamic>));
    }
    edit.tracks[track] = releases;
    return (200, _trackJson(app, edit, track));
  }

  FakePlayRelease _release(
    FakePlayApp app,
    FakePlayEdit edit,
    Map<String, dynamic> json,
  ) {
    final status = json['status'];
    if (status is! String ||
        !const [
          'draft',
          'inProgress',
          'halted',
          'completed',
        ].contains(status)) {
      throw _PlayError(
        400,
        'Invalid release status: $status.',
        'INVALID_ARGUMENT',
      );
    }
    final fraction = json['userFraction'];
    if (status == 'inProgress' &&
        !(fraction is num && fraction > 0 && fraction < 1)) {
      throw const _PlayError(
        400,
        'An inProgress release needs a userFraction above 0 and below 1.',
        'INVALID_ARGUMENT',
      );
    }
    if (status != 'inProgress' && status != 'halted' && fraction != null) {
      throw _PlayError(
        400,
        'A $status release cannot have a userFraction.',
        'INVALID_ARGUMENT',
      );
    }
    final codes = [
      for (final code in json['versionCodes'] as List<dynamic>? ?? const [])
        int.parse(code as String),
    ];
    if (codes.isEmpty) {
      throw const _PlayError(
        400,
        'A release needs at least one version code.',
        'INVALID_ARGUMENT',
      );
    }
    for (final code in codes) {
      if (!edit.bundles.containsKey(code) && !app.bundles.containsKey(code)) {
        throw _PlayError(
          400,
          'Version code $code has not been uploaded.',
          'INVALID_ARGUMENT',
        );
      }
    }
    return FakePlayRelease(
      versionCodes: codes,
      status: status,
      name: json['name'] as String?,
      userFraction: (fraction as num?)?.toDouble(),
      releaseNotes: [
        for (final note in json['releaseNotes'] as List<dynamic>? ?? const [])
          (note as Map<String, dynamic>).cast<String, Object?>(),
      ],
    );
  }

  (int, Object?) _commit(FakePlayApp app, FakePlayEdit edit, Uri uri) {
    final behavior = uri.queryParameters['changesInReviewBehavior'];
    var cancelled = false;
    if (app.reviewInProgress) {
      if (behavior == 'ERROR_IF_IN_REVIEW') {
        commits.add(
          FakePlayCommit(
            editId: edit.id,
            changesInReviewBehavior: behavior,
            status: 400,
            cancelledReview: false,
          ),
        );
        throw _PlayError(
          400,
          'You already have changes in review. Cancel this review or wait for '
              'it to complete before you try again.',
          'FAILED_PRECONDITION',
          infoReason: 'CHANGES_ALREADY_IN_REVIEW',
          metadata: {
            'editId': edit.id,
            'method': 'androidpublisher.edits.commit',
            'service': 'androidpublisher.googleapis.com',
          },
        );
      }
      cancelled = true;
      for (final release in [for (final r in app.tracks.values) ...r]) {
        if (release.inReview) {
          app.cancelledReviews.add(release.name ?? '${release.versionCodes}');
          release.lifecycleState =
              'RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW';
        }
      }
    }
    app.bundles.addAll(edit.bundles);
    for (final MapEntry(key: track, value: releases) in edit.tracks.entries) {
      for (final release in releases) {
        release.lifecycleState = release.status == 'draft'
            ? 'RELEASE_LIFECYCLE_STATE_DRAFT'
            : sendsToReview
            ? _inReview
            : 'RELEASE_LIFECYCLE_STATE_PUBLISHED';
      }
      app.tracks[track] = releases;
    }
    edit.committed = true;
    commits.add(
      FakePlayCommit(
        editId: edit.id,
        changesInReviewBehavior: behavior,
        status: 200,
        cancelledReview: cancelled,
      ),
    );
    return (
      200,
      {
        'id': edit.id,
        'expiryTimeSeconds': '${edit.expiresAt.millisecondsSinceEpoch ~/ 1000}',
      },
    );
  }

  Map<String, Object?> _releaseList(FakePlayApp app, String track) => {
    'releases': [
      for (final release in app.tracks[track] ?? const <FakePlayRelease>[])
        {
          'track': track,
          'releaseName': ?release.name,
          'releaseLifecycleState': release.lifecycleState,
          'activeArtifacts': [
            for (final code in release.versionCodes) {'versionCode': code},
          ],
        },
    ],
  };

  _PlayError _notFound(String message, {String? reason}) =>
      _PlayError(404, message, 'NOT_FOUND', reason: reason);

  static String _hex(List<int> bytes) =>
      [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

  static String _statusName(int status) => switch (status) {
    400 => 'INVALID_ARGUMENT',
    401 => 'UNAUTHENTICATED',
    403 => 'PERMISSION_DENIED',
    404 => 'NOT_FOUND',
    409 => 'ABORTED',
    429 => 'RESOURCE_EXHAUSTED',
    503 => 'UNAVAILABLE',
    _ => 'INTERNAL',
  };
}

class _Failure {
  const new(
    this.status, {
    required this.message,
    required this.reason,
    required this.pathContains,
    required this.method,
  });

  final int status;
  final String message;
  final String? reason;
  final String pathContains;
  final String? method;
}

class _TokenError implements Exception {
  const new(this.error, this.description);

  final String error;
  final String description;
}

/// An error in the shape Google's APIs answer with.
class _PlayError implements Exception {
  const new(
    this.status,
    this.message,
    this.statusName, {
    this.reason,
    this.infoReason,
    this.metadata = const {},
  });

  final int status;
  final String message;
  final String statusName;

  /// The `reason` of `error.errors[0]`.
  final String? reason;

  /// The `reason` of the `ErrorInfo` in `error.details`.
  final String? infoReason;
  final Map<String, String> metadata;

  Map<String, Object?> toJson() => {
    'error': {
      'code': status,
      'message': message,
      'errors': [
        {'message': message, 'domain': 'global', 'reason': ?reason},
      ],
      'status': statusName,
      if (infoReason != null)
        'details': [
          {
            '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
            'reason': infoReason,
            'domain': 'googleapis.com',
            'metadata': metadata,
          },
        ],
    },
  };
}
