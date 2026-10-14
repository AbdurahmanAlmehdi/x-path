/// A release cannot be read or changed.
class ReleaseException implements Exception {
  /// Creates the exception with a [message] for the owner.
  const new(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => 'ReleaseException: $message';
}

/// There is no such release.
class ReleaseNotFoundException extends ReleaseException {
  /// Creates the exception.
  const new(this.id) : super('There is no release $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'ReleaseNotFoundException: $message';
}

/// The release is not in a state that allows the request.
class ReleaseStateException extends ReleaseException {
  /// Creates the exception.
  const new(super.message);

  @override
  String toString() => 'ReleaseStateException: $message';
}

/// The token's kind may not do this (D-13).
class ReleaseForbiddenException extends ReleaseException {
  /// Creates the exception.
  const new(super.message);

  @override
  String toString() => 'ReleaseForbiddenException: $message';
}

/// The request cannot be done: a store the release does not target, or a
/// status the owner cannot set by hand.
class ReleaseRequestException extends ReleaseException {
  /// Creates the exception.
  const new(super.message);

  @override
  String toString() => 'ReleaseRequestException: $message';
}
