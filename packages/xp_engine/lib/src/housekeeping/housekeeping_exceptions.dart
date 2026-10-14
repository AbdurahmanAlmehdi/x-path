/// A housekeeping request failed.
class HousekeepingException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong, for the client.
  final String message;

  @override
  String toString() => 'HousekeepingException: $message';
}

/// The device token's kind may not do this (D-13): deleting is for the app and
/// `xp`.
class HousekeepingForbiddenException extends HousekeepingException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'HousekeepingForbiddenException: $message';
}

/// The settings or the request are not valid.
class HousekeepingRequestException extends HousekeepingException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'HousekeepingRequestException: $message';
}
