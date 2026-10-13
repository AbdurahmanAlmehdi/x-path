/// A git operation failed.
///
/// The message never contains a credential.
class GitException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong, including what git said.
  final String message;

  @override
  String toString() => 'GitException: $message';
}

/// A ref, branch, tag or commit does not exist in the mirror.
class GitRefNotFoundException extends GitException {
  /// Creates an exception for [ref].
  const new(this.ref) : super('Cannot find $ref.');

  /// What was asked for.
  final String ref;

  @override
  String toString() => 'GitRefNotFoundException: $message';
}

/// A tag exists on another commit than the one asked for (D-11).
///
/// A tag is never moved: the caller must pick another name or stop.
class GitTagConflictException extends GitException {
  /// Creates an exception for [tag].
  const new({
    required this.tag,
    required this.existingSha,
    required this.requestedSha,
  }) : super('Tag $tag is on $existingSha, not on $requestedSha.');

  /// The tag name.
  final String tag;

  /// The commit the tag is on.
  final String existingSha;

  /// The commit the tag was asked to be on.
  final String requestedSha;

  @override
  String toString() => 'GitTagConflictException: $message';
}

/// A branch cannot move to the commit asked for without a force.
///
/// The commit is not a descendant of the branch tip. XPath never forces.
class GitBranchConflictException extends GitException {
  /// Creates an exception for [branch].
  const new({
    required this.branch,
    required this.currentSha,
    required this.requestedSha,
  }) : super(
         'Branch $branch is on $currentSha; $requestedSha is not a '
         'descendant of it.',
       );

  /// The branch name.
  final String branch;

  /// The commit the branch is on.
  final String currentSha;

  /// The commit the branch was asked to move to.
  final String requestedSha;

  @override
  String toString() => 'GitBranchConflictException: $message';
}

/// The remote refused a push, for example because it is not a fast-forward or
/// because a tag already exists there on another commit.
class GitPushRejectedException extends GitException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'GitPushRejectedException: $message';
}
