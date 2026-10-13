import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xp_fake_firebase/src/fake_firebase_state.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

/// A fake Firebase App Distribution API and OAuth2 token endpoint on a
/// loopback port.
///
/// It serves the calls XPath makes (`releases:upload` with a raw body, the
/// long-running operation, `releases.list`, `releases.patch`,
/// `releases:distribute`) from state held in memory, in Google's JSON, and the
/// JWT bearer flow at `/token`. It checks the signed assertion like Google
/// does (the `cloud-platform` scope) and the access token on every API call.
///
/// An upload is processed asynchronously like the real thing: its operation
/// answers "not done" for [pollsBeforeDone] polls.
class FakeFirebaseServer {
  new _(
    this._server,
    this._now,
    this._accounts,
    this._lifetime,
    this.pollsBeforeDone,
  ) {
    _verifier = AssertionVerifier(
      accounts: _accounts,
      audience: tokenUri.toString(),
      now: _now,
      scope: fakeFirebaseScope,
    );
    _server.listen(_handle);
  }

  /// Starts a server that accepts assertions of [accounts] (the test account
  /// of `xp_fake_play` by default) and checks their expiry against [now] (the
  /// system clock by default). Access tokens live [tokenLifetime].
  static Future<FakeFirebaseServer> start({
    Iterable<FakePlayAccount> accounts = const [fakePlayTestAccount],
    DateTime Function()? now,
    Duration tokenLifetime = const Duration(hours: 1),
    int pollsBeforeDone = 1,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeFirebaseServer._(
      server,
      now ?? () => DateTime.now().toUtc(),
      accounts.toList(),
      tokenLifetime,
      pollsBeforeDone,
    );
  }

  final HttpServer _server;
  final DateTime Function() _now;
  final List<FakePlayAccount> _accounts;
  final Duration _lifetime;
  late final AssertionVerifier _verifier;
  var _ids = 0;
  final _tokens = <String, DateTime>{};
  final _failures = <_Failure>[];
  var _rateLimited = 0;
  int? _retryAfter;

  /// How many polls of a new upload answer "not done".
  int pollsBeforeDone;

  /// The apps, by Firebase app id.
  final apps = <String, FakeFirebaseApp>{};

  /// The operations, by name.
  final operations = <String, FakeFirebaseOperation>{};

  /// Every request received, oldest first.
  final requests = <FakeFirebaseRequest>[];

  /// The access tokens issued so far.
  int tokensIssued = 0;

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

  /// Adds an app. [appId] looks like `1:123456789012:android:abcdef`.
  FakeFirebaseApp addApp(
    String projectNumber,
    String appId, {
    Set<String>? allowedAccounts,
    Set<String>? groups,
  }) => apps[appId] = FakeFirebaseApp(
    projectNumber,
    appId,
    allowedAccounts: allowedAccounts,
    groups: groups,
  );

  /// Adds a release of [app] without an upload.
  FakeFirebaseRelease addRelease(
    FakeFirebaseApp app, {
    required String displayVersion,
    required String buildVersion,
    String binaryType = 'APK',
    DateTime? createTime,
    String? notes,
  }) {
    final release = FakeFirebaseRelease(
      name: '${app.name}/releases/${'rel-${++_ids}'}',
      displayVersion: displayVersion,
      buildVersion: buildVersion,
      binaryType: binaryType,
      createTime: createTime ?? _now(),
      binary: const [],
    )..notes = notes;
    app.releases.add(release);
    return release;
  }

  /// Forgets every access token, so that the next API call is refused.
  void revokeTokens() => _tokens.clear();

  /// Makes the next request whose path contains [pathContains] (any request
  /// by default) and whose method is [method] (any by default) fail with
  /// [status].
  void failNext(
    int status, {
    String message = 'An error occurred.',
    String pathContains = '',
    String? method,
  }) => _failures.add(
    _Failure(
      status,
      message: message,
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
    final isToken = uri.path == '/token';
    Object? json;
    if (request.headers.contentType?.mimeType == 'application/json' &&
        bytes.isNotEmpty) {
      json = jsonDecode(utf8.decode(bytes));
    }
    final token = request.headers
        .value(HttpHeaders.authorizationHeader)
        ?.replaceFirst(RegExp('^Bearer '), '');
    final tokenProblem = isToken ? null : _tokenProblem(token);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add(
      FakeFirebaseRequest(
        method: request.method,
        uri: uri,
        headers: headers,
        bodyLength: bytes.length,
        body: json,
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
        throw _FirebaseError(401, tokenProblem, 'UNAUTHENTICATED');
      }
      if (_rateLimited > 0) {
        _rateLimited--;
        if (_retryAfter != null) {
          response.headers.set(HttpHeaders.retryAfterHeader, '$_retryAfter');
        }
        throw const _FirebaseError(
          429,
          'Quota exceeded for quota metric.',
          'RESOURCE_EXHAUSTED',
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
        throw _FirebaseError(
          failure.status,
          failure.message,
          _statusName(failure.status),
        );
      }
      final (status, body) = _route(
        request.method,
        uri,
        headers,
        json,
        bytes,
        _emailOf(token!),
      );
      _send(response, status, body);
    } on _FirebaseError catch (error) {
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
    Map<String, String> headers,
    Object? json,
    List<int> bytes,
    String email,
  ) {
    final path = uri.pathSegments;
    final isUpload = path.firstOrNull == 'upload';
    final api = isUpload ? path.sublist(1) : path;
    if (api.length < 5 ||
        api[0] != 'v1' ||
        api[1] != 'projects' ||
        api[3] != 'apps') {
      throw _notFound('No such method: ${uri.path}.');
    }
    final app = _app(api[2], api[4], email);
    final rest = api.sublist(5);
    switch ((method, rest)) {
      case ('POST', ['releases:upload']) when isUpload:
        return _upload(app, headers, bytes);
      case ('GET', ['releases']):
        return (200, _list(app, uri));
      case ('GET', ['releases', _, 'operations', final id]):
        return _operation(app, id);
      case ('PATCH', ['releases', final id]):
        return _patch(app, id, uri, json);
      case ('POST', ['releases', final idAndAction])
          when idAndAction.endsWith(':distribute'):
        return _distribute(
          app,
          idAndAction.substring(0, idAndAction.length - ':distribute'.length),
          json,
        );
      default:
        throw _notFound('No such method: $method ${uri.path}.');
    }
  }

  FakeFirebaseApp _app(String projectNumber, String appId, String email) {
    final app = apps[appId];
    if (app == null || app.projectNumber != projectNumber) {
      throw _notFound('Requested entity was not found.');
    }
    final allowed = app.allowedAccounts;
    if (allowed != null && !allowed.contains(email)) {
      throw const _FirebaseError(
        403,
        'The caller does not have permission',
        'PERMISSION_DENIED',
      );
    }
    return app;
  }

  FakeFirebaseRelease _release(FakeFirebaseApp app, String id) =>
      app.releases
          .where((r) => r.name == '${app.name}/releases/$id')
          .firstOrNull ??
      (throw _notFound('Requested entity was not found.'));

  (int, Object?) _upload(
    FakeFirebaseApp app,
    Map<String, String> headers,
    List<int> bytes,
  ) {
    if (headers['x-goog-upload-protocol'] != 'raw') {
      throw const _FirebaseError(
        400,
        'This fake only takes X-Goog-Upload-Protocol: raw.',
        'INVALID_ARGUMENT',
      );
    }
    if ((headers['x-goog-upload-file-name'] ?? '').isEmpty) {
      throw const _FirebaseError(
        400,
        'X-Goog-Upload-File-Name is needed.',
        'INVALID_ARGUMENT',
      );
    }
    final text = utf8.decode(bytes.take(120).toList(), allowMalformed: true);
    final match = RegExp(
      r'^fake-(apk|aab|ipa) versionName=(\S+) versionCode=(\d+)\n',
    ).firstMatch(text);
    if (match == null) {
      throw const _FirebaseError(
        400,
        'The uploaded file is not a valid APK, AAB or IPA.',
        'INVALID_ARGUMENT',
      );
    }
    final existing = app.releases
        .where(
          (r) => r.displayVersion == match[2] && r.buildVersion == match[3],
        )
        .firstOrNull;
    final FakeFirebaseRelease release;
    final String result;
    if (existing == null) {
      release = FakeFirebaseRelease(
        name: '${app.name}/releases/rel-${++_ids}',
        displayVersion: match[2]!,
        buildVersion: match[3]!,
        binaryType: match[1]!.toUpperCase(),
        createTime: _now(),
        binary: bytes,
      );
      app.releases.add(release);
      result = 'RELEASE_CREATED';
    } else {
      release = existing;
      result = _sameBytes(existing.binary, bytes)
          ? 'RELEASE_UNMODIFIED'
          : 'RELEASE_UPDATED';
      existing.binary = bytes;
    }
    final operation = FakeFirebaseOperation(
      name: '${app.name}/releases/-/operations/op-${++_ids}',
      release: release,
      result: result,
      pollsLeft: pollsBeforeDone,
    );
    operations[operation.name] = operation;
    return (200, _operationJson(operation));
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  (int, Object?) _operation(FakeFirebaseApp app, String id) {
    final operation =
        operations['${app.name}/releases/-/operations/$id'] ??
        (throw _notFound('Operation not found.'));
    if (operation.pollsLeft > 0) operation.pollsLeft--;
    return (200, _operationJson(operation));
  }

  Map<String, Object?> _operationJson(FakeFirebaseOperation operation) {
    final done = operation.pollsLeft == 0;
    return {
      'name': operation.name,
      if (done) 'done': true,
      if (done)
        'response': {
          '@type':
              'type.googleapis.com/google.firebase.appdistribution.v1.'
              'UploadReleaseResponse',
          'result': operation.result,
          'release': operation.release.toJson(),
        },
    };
  }

  Map<String, Object?> _list(FakeFirebaseApp app, Uri uri) {
    final size = (int.tryParse(uri.queryParameters['pageSize'] ?? '') ?? 25)
        .clamp(1, 100);
    final start = int.tryParse(uri.queryParameters['pageToken'] ?? '') ?? 0;
    final newestFirst = app.releases.reversed.toList();
    final end = (start + size).clamp(0, newestFirst.length);
    return {
      'releases': [
        for (final release in newestFirst.sublist(start, end)) release.toJson(),
      ],
      if (end < newestFirst.length) 'nextPageToken': '$end',
    };
  }

  (int, Object?) _patch(FakeFirebaseApp app, String id, Uri uri, Object? json) {
    final release = _release(app, id);
    if (uri.queryParameters['updateMask'] != 'releaseNotes.text') {
      throw const _FirebaseError(
        400,
        'This fake only updates releaseNotes.text.',
        'INVALID_ARGUMENT',
      );
    }
    final notes = json is Map<String, dynamic> ? json['releaseNotes'] : null;
    final text = notes is Map<String, dynamic> ? notes['text'] : null;
    if (text is! String) {
      throw const _FirebaseError(
        400,
        'releaseNotes.text is needed.',
        'INVALID_ARGUMENT',
      );
    }
    release.notes = text;
    return (200, release.toJson());
  }

  (int, Object?) _distribute(FakeFirebaseApp app, String id, Object? json) {
    final release = _release(app, id);
    final fields = json is Map<String, dynamic> ? json : <String, dynamic>{};
    final testers = [
      for (final email in fields['testerEmails'] as List<dynamic>? ?? const [])
        email as String,
    ];
    final groups = [
      for (final alias in fields['groupAliases'] as List<dynamic>? ?? const [])
        alias as String,
    ];
    for (final alias in groups) {
      if (!app.groups.contains(alias)) {
        throw _FirebaseError(
          400,
          'Group $alias does not exist.',
          'INVALID_ARGUMENT',
        );
      }
    }
    release.distributions.add(
      'testers=${testers.join(',')} groups=${groups.join(',')}',
    );
    return (200, const <String, Object?>{});
  }

  _FirebaseError _notFound(String message) =>
      _FirebaseError(404, message, 'NOT_FOUND');

  static String _statusName(int status) => switch (status) {
    400 => 'INVALID_ARGUMENT',
    401 => 'UNAUTHENTICATED',
    403 => 'PERMISSION_DENIED',
    404 => 'NOT_FOUND',
    409 => 'ABORTED',
    429 => 'RESOURCE_EXHAUSTED',
    >= 500 => 'INTERNAL',
    _ => 'UNKNOWN',
  };
}

class _Failure {
  new(
    this.status, {
    required this.message,
    required this.pathContains,
    this.method,
  });

  final int status;
  final String message;
  final String pathContains;
  final String? method;
}

class _FirebaseError implements Exception {
  const new(this.status, this.message, this.statusName);

  final int status;
  final String message;
  final String statusName;

  Map<String, Object?> toJson() => {
    'error': {'code': status, 'message': message, 'status': statusName},
  };
}

class _TokenError implements Exception {
  const new(this.error, this.description);

  final String error;
  final String description;
}
