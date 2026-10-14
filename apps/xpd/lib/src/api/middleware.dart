import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/responses.dart';

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

final _bearer = RegExp(r'^Bearer\s+(\S+)$', caseSensitive: false);

const _tokenContextKey = 'xpd.deviceToken';

/// The device token that authenticated [request]: its kind decides what the
/// request may do (D-13).
///
/// Only requests that went through [authMiddleware] and are not to a public
/// path carry one.
DeviceToken deviceTokenOf(Request request) =>
    request.context[_tokenContextKey]! as DeviceToken;

/// Requires `Authorization: Bearer <device token>` on every request except
/// those to [publicPaths], and hands the token to the handlers
/// ([deviceTokenOf]).
Middleware authMiddleware(
  TokenService tokens, {
  Set<String> publicPaths = const {},
}) =>
    (inner) => (request) async {
      if (publicPaths.contains(request.requestedUri.path)) {
        return await inner(request);
      }
      final header = request.headers['authorization'];
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
  final path = request.requestedUri.path;
  return (request.method == 'GET' &&
          (path == '/runners/connect' || path == '/runners/bundle')) ||
      (request.method == 'PUT' && _artifactUpload.hasMatch(path));
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
          token.kind == DeviceTokenKind.runner &&
          !_runnerMayReach(request)) {
        return errorResponse(
          ApiErrorCode.forbidden,
          'A runner token reaches only the runner connection '
          '(GET /runners/connect), the runner bundle '
          '(GET /runners/bundle) and the artifact upload of a job it holds '
          '(PUT /runners/jobs/{id}/artifacts/{name}), not '
          '${request.method} ${request.requestedUri.path}.',
        );
      }
      return await inner(request);
    };
