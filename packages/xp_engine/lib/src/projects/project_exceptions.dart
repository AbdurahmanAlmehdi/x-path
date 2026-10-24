/// A project operation failed.
class ProjectException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong. Never contains a credential.
  final String message;

  @override
  String toString() => 'ProjectException: $message';
}

/// There is no project with the id asked for.
class ProjectNotFoundException extends ProjectException {
  /// Creates an exception for [id].
  const new(this.id) : super('There is no project $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'ProjectNotFoundException: $message';
}

/// The repository is a project already (D-05, ADR 0015: projects are keyed
/// by their source key).
class ProjectExistsException extends ProjectException {
  /// Creates an exception for the project [existingId].
  const new(this.existingId, String fullName)
    : super('$fullName is project $existingId already.');

  /// The id of the project that has the repository.
  final String existingId;

  @override
  String toString() => 'ProjectExistsException: $message';
}

/// The request cannot be carried out as it stands: a path that is not a
/// folder, a folder without a remote XPath can reach, or an edit of something
/// the profile does not have.
class ProjectInvalidException extends ProjectException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'ProjectInvalidException: $message';
}

/// The origin is an HTTPS URL on a host other than GitHub. XPath has no
/// credentials for it, so it offers the SSH URL of the same repository, which
/// the owner confirms by adding the project again with it (ADR 0015).
class ProjectSshUrlRequiredException extends ProjectInvalidException {
  /// Creates the exception for an origin on [host] whose SSH URL is
  /// [sshUrl].
  const new({required this.host, required this.sshUrl})
    : super(
        'XPath has no credentials for $host over HTTPS; use the SSH URL '
        '$sshUrl.',
      );

  /// The host of the origin.
  final String host;

  /// The SSH URL XPath derived from the origin.
  final String sshUrl;

  @override
  String toString() => 'ProjectSshUrlRequiredException: $message';
}

/// The project cannot be removed because releases or jobs refer to it. Their
/// history is kept.
class ProjectInUseException extends ProjectException {
  /// Creates an exception for [id].
  const new(this.id)
    : super('Project $id has releases or jobs, so it cannot be removed.');

  /// The project.
  final String id;

  @override
  String toString() => 'ProjectInUseException: $message';
}
