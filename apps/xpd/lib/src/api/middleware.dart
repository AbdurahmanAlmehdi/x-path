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
