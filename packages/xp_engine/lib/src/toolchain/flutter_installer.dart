/// XPath's own cache of Flutter SDKs, for machines without fvm (D-20).
///
/// `xp_adapters` has the `dart:io` implementation, which clones the SDK with
/// `git`.
abstract interface class FlutterInstaller {
  /// Where the SDK of the exact [version] lives, whether or not it is
  /// installed.
  String pathFor(String version);

  /// Whether the SDK of [version] is in the cache.
  Future<bool> isInstalled(String version);

  /// Downloads the SDK of [version] into the cache and prepares it, so that
  /// the first build does not have to.
  ///
  /// Throws a [FlutterInstallException] if that fails; nothing is left behind
  /// in the cache then.
  Future<void> install(String version);
}

/// A Flutter SDK could not be installed.
class FlutterInstallException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'FlutterInstallException: $message';
}
