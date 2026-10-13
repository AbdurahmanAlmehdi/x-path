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

/// Requires `Authorization: Bearer <device token>` on every request except
/// those to [publicPaths].
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
      if (await tokens.authenticate(secret) == null) {
        return errorResponse(
          ApiErrorCode.unauthorized,
          'Missing, unknown or revoked bearer token.',
          headers: const {'www-authenticate': 'Bearer'},
        );
      }
      return await inner(request);
    };
