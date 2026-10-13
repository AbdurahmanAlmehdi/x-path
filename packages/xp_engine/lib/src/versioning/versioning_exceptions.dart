/// A version file cannot be read or written.
class VersionFileException implements Exception {
  /// Creates an exception for [path].
  const new(this.path, this.message);

  /// The file, relative to the repository root.
  final String path;

  /// What is wrong with it.
  final String message;

  @override
  String toString() => 'VersionFileException: $path: $message';
}

/// The project has no app at the path asked for, so there is no build counter.
class UnknownAppException implements Exception {
  /// Creates an exception for the app at [appPath] of [projectId].
  const new(this.projectId, this.appPath);

  /// The project.
  final String projectId;

  /// The app directory relative to the repository root.
  final String appPath;

  @override
  String toString() =>
      'UnknownAppException: project $projectId has no app at $appPath.';
}
