/// A GitHub call failed. The message never contains the token.
class GitHubException implements Exception {
  /// Creates an exception for HTTP [statusCode].
  const new(this.statusCode, this.message);

  /// The HTTP status code, or `0` when there was no usable response.
  final int statusCode;

  /// What went wrong, as GitHub said it where possible.
  final String message;

  @override
  String toString() => 'GitHubException($statusCode): $message';
}

/// 401, or no token at all: the token is missing, expired or revoked.
class GitHubAuthException extends GitHubException {
  /// Creates an exception with [message].
  const new(String message) : super(401, message);

  @override
  String toString() => 'GitHubAuthException: $message';
}

/// 403: the token may not do this, or GitHub is rate limiting it.
class GitHubForbiddenException extends GitHubException {
  /// Creates an exception with [message].
  const new(String message, {this.rateLimited = false}) : super(403, message);

  /// Whether the cause is the rate limit rather than missing permission.
  final bool rateLimited;

  @override
  String toString() => 'GitHubForbiddenException: $message';
}

/// 404: the repository or pull request does not exist, or the token cannot
/// see it.
class GitHubNotFoundException extends GitHubException {
  /// Creates an exception with [message].
  const new(String message) : super(404, message);

  @override
  String toString() => 'GitHubNotFoundException: $message';
}

/// 405: the pull request cannot be merged now, for example because checks or
/// reviews are missing, or it is already merged.
class GitHubNotMergeableException extends GitHubException {
  /// Creates an exception with [message].
  const new(String message) : super(405, message);

  @override
  String toString() => 'GitHubNotMergeableException: $message';
}

/// 409: the head of the pull request is not the commit that was expected, so
/// the merge was refused.
class GitHubConflictException extends GitHubException {
  /// Creates an exception with [message].
  const new(String message) : super(409, message);

  @override
  String toString() => 'GitHubConflictException: $message';
}

/// 422: GitHub rejected the request, for example a pull request that already
/// exists for the branches or has no commits between them.
class GitHubValidationException extends GitHubException {
  /// Creates an exception with [message].
  const new(String message) : super(422, message);

  @override
  String toString() => 'GitHubValidationException: $message';
}
