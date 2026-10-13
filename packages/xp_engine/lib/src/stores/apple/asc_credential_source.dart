import 'package:xp_engine/src/stores/apple/asc_key.dart';

/// Where the engine finds the App Store Connect API key for an app.
///
/// `xp_adapters` reads the `asc_key` credential reference of the flavor with
/// the bundle id and the key from the secret store.
abstract interface class AscCredentialSource {
  /// The key for the app with iOS bundle id [bundleId], or `null` if no
  /// flavor with that bundle id has one (an Apple ID flavor, or none set up).
  Future<AscKey?> forBundleId(String bundleId);
}

/// An [AscCredentialSource] with the keys the test gives it.
class FakeAscCredentialSource implements AscCredentialSource {
  /// Creates a source that holds [keys], by bundle id.
  new([Map<String, AscKey>? keys]) : keys = keys ?? {};

  /// The keys, by bundle id.
  final Map<String, AscKey> keys;

  /// Every bundle id asked for, oldest first.
  final lookups = <String>[];

  @override
  Future<AscKey?> forBundleId(String bundleId) async {
    lookups.add(bundleId);
    return keys[bundleId];
  }
}
