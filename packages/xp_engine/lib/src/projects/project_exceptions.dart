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

/// The GitHub repository is a project already (D-05: projects are keyed by
/// the repository id).
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
/// folder, a folder without a GitHub remote, or an edit of something the
/// profile does not have.
class ProjectInvalidException extends ProjectException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'ProjectInvalidException: $message';
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
