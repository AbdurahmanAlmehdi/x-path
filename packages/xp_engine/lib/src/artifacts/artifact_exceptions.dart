/// There is no artifact with the id asked for, or its file is gone.
class ArtifactNotFoundException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What is missing.
  final String message;

  @override
  String toString() => 'ArtifactNotFoundException: $message';
}
