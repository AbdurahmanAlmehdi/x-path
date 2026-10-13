import 'package:xp_api/xp_api.dart';

/// Takes the compiled Dart code out of an app package.
///
/// `xp_adapters` has the implementation, which unzips the package.
abstract interface class SnapshotReader {
  /// The bytes of the AOT snapshot in the package whose content is [package]:
  /// `lib/<abi>/libapp.so` of an [ArtifactKind.apk], `base/lib/<abi>/libapp.so`
  /// of an [ArtifactKind.aab] and `Payload/<name>.app/Frameworks/App.framework/App`
  /// of an [ArtifactKind.ipa].
  ///
  /// Returns `null` if the package has none. Throws a [FormatException] if
  /// [package] is not a ZIP archive.
  Future<Stream<List<int>>?> snapshotOf(
    ArtifactKind kind,
    Stream<List<int>> package,
  );
}
