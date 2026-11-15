import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/allowed_origins.dart';
import 'package:xpd/src/api/legacy_alias.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/session/session_cookie.dart';

/// Refuses, with `405 method_not_allowed`, a request whose method is not in
/// upper case, before anything else reads it.
///
/// `shelf_router` matches a route on the upper-cased method, while every
/// check in front of it compares the method as sent: `patch` would reach
/// the `PATCH` handler without the checks that `PATCH` gets. Put this
/// middleware in front of the whole pipeline (the root aliases included),
/// so that every check after it sees the method the router sees.
Middleware canonicalMethodMiddleware() =>
    (inner) => (request) {
      final method = request.method;
      final upper = method.toUpperCase();
      if (method == upper) return inner(request);
      return errorResponse(
        ApiErrorCode.methodNotAllowed,
        'The engine takes methods in upper case only: send $upper, not '
        '$method.',
        headers: const {'allow': 'GET, HEAD, POST, PUT, PATCH, DELETE'},
      );
    };

/// The method of [request] in upper case, as `shelf_router` matches it.
String methodOf(Request request) => request.method.toUpperCase();

/// Turns an exception that escapes a handler into a `500 internal` response.
///
/// The response never says what went wrong; [onError] receives the details.
Middleware errorMiddleware({
  void Function(Object error, StackTrace stackTrace)? onError,
}) =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on HijackException {
        // The WebSocket upgrade took over the socket; not a failure.
        rethrow;
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
        return errorResponse(
          ApiErrorCode.internal,
          'The engine failed to handle the request.',
        );
      }
    };

/// Tells [onRefused] about a runner connection (`GET /runners/connect`)
/// that was turned away before the WebSocket opened: who asked and why.
///
/// Add it before [authMiddleware]: it sees the `401` that one answers.
Middleware runnerRefusalMiddleware(
  void Function(String address, String why) onRefused,
) =>
    (inner) => (request) async {
      final response = await inner(request);
      if (_pathOf(request) != '/runners/connect') return response;
      final why = switch (response.statusCode) {
        401 => 'an unknown or revoked credential (401)',
        403 => 'not a runner token (403)',
        426 => 'not a WebSocket upgrade (426)',
        _ => null,
      };
      if (why != null) onRefused(_addressOf(request), why);
      return response;
    };

/// The path of [request] within the API, whether it came under `/api/v1` or
/// to its root alias.
String _pathOf(Request request) => '/${request.url.path}';

String _addressOf(Request request) =>
    AllowedOrigins.remoteAddressOf(request) ?? 'an unknown address';

final _bearer = RegExp(r'^Bearer\s+(\S+)$', caseSensitive: false);

const _tokenContextKey = 'xpd.deviceToken';

const _cookieContextKey = 'xpd.sessionCookie';

/// The device token that authenticated [request]: its kind and its person's
/// role decide what the request may do (ADR 0017).
///
/// Only requests that went through [authMiddleware] and are not to a public
/// path carry one.
DeviceToken deviceTokenOf(Request request) =>
    request.context[_tokenContextKey]! as DeviceToken;

/// The device token that authenticated [request], or `null` for a request
/// to a public path.
DeviceToken? deviceTokenIfAny(Request request) =>
    request.context[_tokenContextKey] as DeviceToken?;

/// Whether the session cookie, not a bearer token, authenticated
/// [request]: the CSRF rules apply to it (D14).
bool authenticatedByCookie(Request request) =>
    request.context[_cookieContextKey] == true;

/// Requires a device token on every request except those to [publicPaths]
/// and the `METHOD /path` routes of [publicRoutes], and hands the token to
/// the handlers ([deviceTokenOf]).
///
/// The token is `Authorization: Bearer <device token>`, or, under `/api/v1`
/// only and only without `Authorization`, the session cookie of a browser,
/// which authenticates a `web` token and no other (ADR 0018, D3a). A request
/// with `Authorization` is a bearer request: its cookie is never read.
Middleware authMiddleware(
  TokenService tokens, {
  Set<String> publicPaths = const {},
  Set<String> publicRoutes = const {},
}) =>
    (inner) => (request) async {
      final path = _pathOf(request);
      if (publicPaths.contains(path) ||
          publicRoutes.contains('${methodOf(request)} $path')) {
        return await inner(request);
      }
      final header = request.headers['authorization'];
      if (header == null && isUnderApiMount(request)) {
        for (final secret in SessionCookie.secretsOf(request)) {
          final token = await tokens.authenticate(secret);
          if (token != null && AccessPolicy.mayUseSessionCookie(token)) {
            return await inner(
              request.change(
                context: {_tokenContextKey: token, _cookieContextKey: true},
              ),
            );
          }
        }
      }
      final secret = header == null
          ? null
          : _bearer.firstMatch(header)?.group(1);
      final token = await tokens.authenticate(secret);
      if (token == null) {
        return errorResponse(
          ApiErrorCode.unauthorized,
          'Missing, unknown or revoked bearer token.',
          headers: const {'www-authenticate': 'Bearer'},
        );
      }
      return await inner(request.change(context: {_tokenContextKey: token}));
    };

/// What a `runner` token may reach (ADR 0011): the connection it dials out on,
/// the upload of an artifact of a job it holds and the download of the bundle
/// it updates itself with, and nothing else.
bool _runnerMayReach(Request request) {
  final path = _pathOf(request);
  final method = methodOf(request);
  return (method == 'GET' &&
          (path == '/runners/connect' || path == '/runners/bundle')) ||
      (method == 'PUT' && _artifactUpload.hasMatch(path));
}

final _artifactUpload = RegExp(r'^/runners/jobs/[^/]+/artifacts/[^/]+$');

/// Keeps a `runner` token to the runner endpoints (ADR 0011): every other
/// route answers `403 forbidden` with a message that says so, whatever the
/// route would have done with the token otherwise. A runner holds signing
/// material for the one job it leases, so it must not be able to read
/// projects, jobs or credentials, or to change anything.
///
/// Add it after [authMiddleware]: it reads the token that middleware found.
/// The routes that need no token ([authMiddleware]'s `publicPaths`) are not
/// affected.
Middleware runnerScopeMiddleware() =>
    (inner) => (request) async {
      final token = request.context[_tokenContextKey];
      if (token is DeviceToken &&
          AccessPolicy.isRunner(token) &&
          !_runnerMayReach(request)) {
        return errorResponse(
          ApiErrorCode.forbidden,
          'A runner token reaches only the runner connection '
          '(GET /runners/connect), the runner bundle '
          '(GET /runners/bundle) and the artifact upload of a job it holds '
          '(PUT /runners/jobs/{id}/artifacts/{name}), not '
          '${methodOf(request)} ${_pathOf(request)}.',
        );
      }
      return await inner(request);
    };
