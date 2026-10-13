/// A job operation failed.
class JobException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'JobException: $message';
}

/// There is no job with the id asked for.
class JobNotFoundException extends JobException {
  /// Creates an exception for [id].
  const new(this.id) : super('There is no job $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'JobNotFoundException: $message';
}

/// The job is in a state that does not allow the operation, for example
/// cancelling a job that has ended.
class JobStateException extends JobException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'JobStateException: $message';
}

/// The request cannot be carried out as it stands, for example a step to
/// resume from that the job does not have.
class JobInvalidException extends JobException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'JobInvalidException: $message';
}
