/// An App Store Connect call failed. The message never contains a key or a
/// token.
class AppStoreConnectException implements Exception {
  /// Creates an exception for HTTP [statusCode].
  const new(this.statusCode, this.message, {this.code, this.fix});

  /// The HTTP status code, or `0` when there was no usable response.
  final int statusCode;

  /// What went wrong, as App Store Connect said it where possible.
  final String message;

  /// The error code of the API (`NOT_AUTHORIZED`, `ENTITY_ERROR...`), if it
  /// sent one.
  final String? code;

  /// What the owner can do about it.
  final String? fix;

  @override
  String toString() => 'AppStoreConnectException($statusCode): $message';
}

/// 401: the token was refused.
class AscAuthException extends AppStoreConnectException {
  /// Creates an exception with [message].
  const new(String message, {super.code})
    : super(
        401,
        message,
        fix:
            'Check the key id, the issuer id and the key kind (team or '
            "individual) of the ASC key, and that this machine's clock is "
            'right. A revoked key must be replaced.',
      );
}

/// 403: the key may not do this.
class AscForbiddenException extends AppStoreConnectException {
  /// Creates an exception with [message].
  const new(String message, {super.code})
    : super(
        403,
        message,
        fix:
            "The key's role does not allow this. Use a key with the App "
            'Manager or Admin role, and accept any new agreement in App '
            'Store Connect.',
      );
}

/// 404: the app, build or version does not exist, or the key cannot see it.
class AscNotFoundException extends AppStoreConnectException {
  /// Creates an exception with [message].
  const new(String message, {super.code})
    : super(
        404,
        message,
        fix: 'Check the app id and that the key belongs to the right team.',
      );
}

/// 409: the request conflicts with the state of the resource.
class AscConflictException extends AppStoreConnectException {
  /// Creates an exception with [message].
  const new(String message, {super.code})
    : super(
        409,
        message,
        fix: 'Read the state again; it changed or the action does not fit it.',
      );
}

/// 422: the request was well formed but App Store Connect refused it.
class AscValidationException extends AppStoreConnectException {
  /// Creates an exception with [message].
  const new(String message, {super.code})
    : super(
        422,
        message,
        fix: 'Fix what the message says in App Store Connect and try again.',
      );
}

/// 429: the key used its hourly quota, or sent too many requests at once.
class AscRateLimitedException extends AppStoreConnectException {
  /// Creates an exception with [message]. [retryAfter] is how long Apple
  /// said to wait, if it said.
  const new(String message, {this.retryAfter, super.code})
    : super(
        429,
        message,
        fix:
            'The key hit its rate limit (per rolling hour). Wait and try '
            'again; read less often.',
      );

  /// How long to wait before the next call, from `Retry-After`.
  final Duration? retryAfter;
}

/// 5xx, or an answer that is not the documented JSON.
class AscServerException extends AppStoreConnectException {
  /// Creates an exception for HTTP [statusCode].
  const new(super.statusCode, super.message, {super.code})
    : super(fix: 'App Store Connect has a problem; try again later.');
}
