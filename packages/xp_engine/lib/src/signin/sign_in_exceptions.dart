/// Signing in to the web dashboard failed. The message is for the person at
/// the browser, and never says more than they may know.
sealed class SignInException implements Exception {
  /// Creates the exception with a [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'SignInException: $message';
}

/// The code is unknown, used or expired: the three are told apart to no one
/// (D10).
class SignInRejectedException extends SignInException {
  /// Creates the exception.
  const new()
    : super(
        'That sign-in code does not work: it is wrong, used or expired. Ask '
        'for a new one.',
      );
}

/// Too many wrong codes in a short time (D10): no code is taken until
/// [retryAfter] has passed.
class SignInRateLimitedException extends SignInException {
  /// Creates the exception.
  const new(this.retryAfter)
    : super(
        'Too many wrong sign-in codes. Wait a few minutes, then try again.',
      );

  /// How long until a code is taken again.
  final Duration retryAfter;
}

/// The token may not issue a sign-in code for that person (D9).
class SignInForbiddenException extends SignInException {
  /// Creates the exception.
  const new()
    : super(
        'Only an admin issues sign-in codes for others; a person gets one for '
        'themself from the app or `xp dashboard`.',
      );
}

/// The public URL is not an HTTPS origin.
class PublicUrlInvalidException extends SignInException {
  /// Creates the exception with a [message] that says why.
  const new(super.message);
}
