import 'package:xp_engine/src/stores/play/play_service_account.dart';

/// Where the engine finds the Google service account for an app.
///
/// `xp_adapters` reads the `play_sa` credential reference of the flavor with
/// the application id and the key from the secret store.
abstract interface class PlayCredentialSource {
  /// The service account for the app with Android application id
  /// [androidAppId], or `null` if no flavor with that id has one: the app is
  /// released to Play by hand (D-15).
  Future<PlayServiceAccount?> forAndroidAppId(String androidAppId);
}

/// A [PlayCredentialSource] with the accounts the test gives it.
class FakePlayCredentialSource implements PlayCredentialSource {
  /// Creates a source that holds [accounts], by application id.
  new([Map<String, PlayServiceAccount>? accounts]) : accounts = accounts ?? {};

  /// The accounts, by application id.
  final Map<String, PlayServiceAccount> accounts;

  /// Every application id asked for, oldest first.
  final lookups = <String>[];

  @override
  Future<PlayServiceAccount?> forAndroidAppId(String androidAppId) async {
    lookups.add(androidAppId);
    return accounts[androidAppId];
  }
}
