/// Where the secrets a job passes to its processes as files are kept.
///
/// Each file is readable by the engine's user only (mode 0600) and the files
/// of a job are deleted when it ends and when the engine starts. `xp_adapters`
/// has the `dart:io` implementation.
abstract interface class SecretFileStore {
  /// Writes [contents] to a new file of the job [jobId] and returns its path.
  Future<String> write(String jobId, String name, String contents);

  /// Deletes every file of the job [jobId].
  Future<void> deleteAll(String jobId);
}

/// A [SecretFileStore] in memory, for tests.
class InMemorySecretFileStore implements SecretFileStore {
  /// The files that exist, by path.
  final files = <String, String>{};

  /// Every file that was ever written, by path, deleted or not.
  final written = <String, String>{};

  /// The jobs whose files were deleted, in order.
  final deleted = <String>[];

  @override
  Future<String> write(String jobId, String name, String contents) async {
    final path = '/secrets/$jobId/$name';
    files[path] = written[path] = contents;
    return path;
  }

  @override
  Future<void> deleteAll(String jobId) async {
    deleted.add(jobId);
    files.removeWhere((path, _) => path.startsWith('/secrets/$jobId/'));
  }
}
