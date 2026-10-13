/// A Firebase App Distribution call failed. The message never contains a key
/// or a token.
class FirebaseException implements Exception {
  /// Creates an exception for HTTP [statusCode].
  const new(this.statusCode, this.message, {this.reason, this.fix});

  /// The HTTP status code, or `0` when there was no usable response.
  final int statusCode;

  /// What went wrong, as Google said it where possible.
  final String message;

  /// The machine-readable reason (`invalid_grant`, `PERMISSION_DENIED`, ...),
  /// if Google sent one.
  final String? reason;

  /// What the owner can do about it.
  final String? fix;

  @override
  String toString() => 'FirebaseException($statusCode): $message';
}

/// 401, or the token endpoint refused the service account: the credentials
/// are not accepted.
class FirebaseAuthException extends FirebaseException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        401,
        message,
        fix:
            'Check the service account key (not deleted, not disabled) and '
            "that this machine's clock is right. A deleted key must be "
            'replaced.',
      );
}

/// 403: the service account may not do this.
class FirebaseForbiddenException extends FirebaseException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        403,
        message,
        fix:
            'Enable the Firebase App Distribution API for the Google Cloud '
            'project and give the service account the role Firebase App '
            'Distribution Admin.',
      );
}

/// 404: the app or the release does not exist, or the account cannot see it.
class FirebaseNotFoundException extends FirebaseException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        404,
        message,
        fix:
            'Check the Firebase app id, and that the app is registered for '
            'App Distribution in the Firebase console.',
      );
}

/// 400 and other 4xx: Firebase refused the request itself (a group that does
/// not exist, a binary it cannot read).
class FirebaseValidationException extends FirebaseException {
  /// Creates an exception for HTTP [statusCode].
  const new(super.statusCode, super.message, {super.reason})
    : super(fix: 'Fix what the message says and try again.');
}

/// 429: too many requests.
class FirebaseRateLimitedException extends FirebaseException {
  /// Creates an exception with [message]. [retryAfter] is how long Google
  /// said to wait, if it said.
  const new(String message, {this.retryAfter, super.reason})
    : super(
        429,
        message,
        fix: 'Firebase is throttling this project. Wait and try again.',
      );

  /// How long to wait before the next call, from `Retry-After`.
  final Duration? retryAfter;
}

/// 5xx, or an answer that is not the documented JSON.
class FirebaseServerException extends FirebaseException {
  /// Creates an exception for HTTP [statusCode].
  const new(super.statusCode, super.message, {super.reason})
    : super(fix: 'Firebase has a problem; try again later.');
}

/// The upload was accepted but Firebase could not process the binary: the
/// long-running operation ended with an error.
class FirebaseOperationFailedException extends FirebaseException {
  /// Creates an exception with the [message] of the operation's error.
  const new(String message)
    : super(
        0,
        message,
        fix:
            'Firebase could not process the binary. Check that it is an APK, '
            'AAB or IPA of the registered app and build it again.',
      );
}
