/// A runner operation failed.
class RunnerException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'RunnerException: $message';
}

/// There is no runner with the id asked for.
class RunnerNotFoundException extends RunnerException {
  /// Creates an exception for [id].
  const new(this.id) : super('There is no runner $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'RunnerNotFoundException: $message';
}

/// The token's kind may not do this: only `app` and `cli` tokens pair and
/// revoke runners, and only a `runner` token connects as one.
class RunnerForbiddenException extends RunnerException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'RunnerForbiddenException: $message';
}

/// A pairing token cannot be exchanged: it is unknown, expired or used.
class PairingRejectedException extends RunnerException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'PairingRejectedException: $message';
}

/// A runner is called that already.
class RunnerNameTakenException extends RunnerException {
  /// Creates an exception for [name].
  const new(this.name)
    : super(
        'A runner called "$name" exists already (revoked runners keep their '
        'name). Choose another name.',
      );

  /// The name.
  final String name;

  @override
  String toString() => 'RunnerNameTakenException: $message';
}

/// The request cannot be carried out as it stands, for example a blank name.
class RunnerInvalidException extends RunnerException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'RunnerInvalidException: $message';
}

/// The runner does not hold the lease it acted on: it ran out, the job was
/// cancelled, or the lease belongs to another runner.
class RunnerLeaseException extends RunnerException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'RunnerLeaseException: $message';
}

/// An uploaded file is not the one the runner declared.
class ArtifactChecksumException extends RunnerException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'ArtifactChecksumException: $message';
}
