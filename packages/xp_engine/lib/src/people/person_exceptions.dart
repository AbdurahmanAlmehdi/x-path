/// A person operation failed. The message is for the owner.
class PersonException implements Exception {
  /// Creates the exception with a [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'PersonException: $message';
}

/// There is no such person, or they were removed.
class PersonNotFoundException extends PersonException {
  /// Creates the exception for [id].
  const new(this.id) : super('There is no person $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'PersonNotFoundException: $message';
}

/// The change would leave the engine in a state it refuses: no active admin,
/// or two active people with one name (ADR 0017).
class PersonConflictException extends PersonException {
  /// Creates the exception with a [message] that says why.
  const new(super.message);

  @override
  String toString() => 'PersonConflictException: $message';
}

/// The request is malformed: a blank or too long name.
class PersonRequestException extends PersonException {
  /// Creates the exception with a [message].
  const new(super.message);

  @override
  String toString() => 'PersonRequestException: $message';
}
