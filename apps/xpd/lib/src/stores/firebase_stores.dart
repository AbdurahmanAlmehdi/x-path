import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// The Firebase App Distribution side of the stores, wired for `xpd serve`: a
/// REST client per service account and the `upload.firebase` step (D-16).
///
/// The service account of a step is named in its input
/// (`serviceAccountSecret`, the secret key of a `firebase_sa` credential).
class FirebaseStores {
  /// Creates the wiring.
  ///
  /// `baseUrl` replaces Google's server in tests.
  new({required this._clock, this._baseUrl});

  final Clock _clock;
  final Uri? _baseUrl;
  final _clients = <PlayServiceAccount, HttpFirebaseAppDistribution>{};

  /// The client for [account]: one per account, so that its token is reused.
  FirebaseAppDistribution connect(PlayServiceAccount account) =>
      _clients.putIfAbsent(
        account,
        () => HttpFirebaseAppDistribution(
          account: account,
          clock: _clock,
          baseUrl: _baseUrl,
        ),
      );

  /// The `upload.firebase` step, uploading from the artifact [store].
  UploadFirebaseStep uploadStep({
    required ArtifactRepository repository,
    required ArtifactStore store,
    required SecretStore secrets,
  }) => UploadFirebaseStep(
    repository: repository,
    store: store,
    secrets: secrets,
    connect: connect,
  );

  /// Releases the HTTP clients.
  void close() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}
