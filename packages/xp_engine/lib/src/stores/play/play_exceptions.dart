/// A Google Play call failed. The message never contains a key or a token.
class PlayException implements Exception {
  /// Creates an exception for HTTP [statusCode].
  const new(this.statusCode, this.message, {this.reason, this.fix});

  /// The HTTP status code, or `0` when there was no usable response.
  final int statusCode;

  /// What went wrong, as Google said it where possible.
  final String message;

  /// The machine-readable reason (`CHANGES_ALREADY_IN_REVIEW`,
  /// `invalid_grant`, ...), if Google sent one.
  final String? reason;

  /// What the owner can do about it.
  final String? fix;

  @override
  String toString() => 'PlayException($statusCode): $message';
}

/// 401, or the token endpoint refused the service account: the credentials
/// are not accepted.
class PlayAuthException extends PlayException {
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
class PlayForbiddenException extends PlayException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        403,
        message,
        fix:
            'Enable the Google Play Android Developer API for the Google '
            'Cloud project, invite the service account in the Play Console '
            '(Users and permissions) and give it permission to release this '
            'app.',
      );
}

/// 404: the app or the edit does not exist, or the account cannot see it.
class PlayNotFoundException extends PlayException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        404,
        message,
        fix:
            'Check the application id and that the app exists in the Play '
            'Console. An edit expires after a while; start again.',
      );
}

/// Changes of the app are in review, and the commit refused to cancel that
/// review (`changesInReviewBehavior=ERROR_IF_IN_REVIEW`). The edit is still
/// valid and the review is untouched.
class PlayReviewInProgressException extends PlayException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        400,
        message,
        fix:
            'Wait for the review to finish, or cancel it in the Play '
            'Console, and run the step again.',
      );
}

/// The version code was used before; Play never accepts one twice.
class PlayVersionCodeUsedException extends PlayException {
  /// Creates an exception for HTTP [statusCode].
  const new(super.statusCode, super.message, {super.reason})
    : super(
        fix:
            'Allocate a new build number and build again; Google Play '
            'refuses a version code it has seen.',
      );
}

/// 409: the edit conflicts with a change made elsewhere (in the Play
/// Console, or by another edit).
class PlayConflictException extends PlayException {
  /// Creates an exception with [message].
  const new(String message, {super.reason})
    : super(
        409,
        message,
        fix:
            'The app changed while the edit was open (a change in the Play '
            'Console invalidates it). Run the step again.',
      );
}

/// 400 and other 4xx: Google Play refused the request itself.
class PlayValidationException extends PlayException {
  /// Creates an exception for HTTP [statusCode].
  const new(super.statusCode, super.message, {super.reason})
    : super(fix: 'Fix what the message says and try again.');
}

/// 429: too many requests (the quota is 3000 per minute).
class PlayRateLimitedException extends PlayException {
  /// Creates an exception with [message]. [retryAfter] is how long Google
  /// said to wait, if it said.
  const new(String message, {this.retryAfter, super.reason})
    : super(
        429,
        message,
        fix: 'Google Play is throttling this project. Wait and try again.',
      );

  /// How long to wait before the next call, from `Retry-After`.
  final Duration? retryAfter;
}

/// 5xx, or an answer that is not the documented JSON.
class PlayServerException extends PlayException {
  /// Creates an exception for HTTP [statusCode].
  const new(super.statusCode, super.message, {super.reason})
    : super(fix: 'Google Play has a problem; try again later.');
}
