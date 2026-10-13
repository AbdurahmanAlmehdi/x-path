import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/stores/apple_stores.dart';
import 'package:xpd/src/stores/firebase_stores.dart';
import 'package:xpd/src/stores/play_stores.dart';

/// The credentials of the flavors, wired for `xpd serve`: the service with a
/// verifier per kind, the daily health check and the `credentials` guard
/// check that fails preflight on what the checks recorded.
///
/// Every verifier asks the real thing with the real client of the stores
/// (App Store Connect, Google Play, Firebase), `altool`, `keytool`, the
/// Shorebird CLI or GitHub, so a credential is accepted only if the place it
/// is for accepts it.
class CredentialChecks {
  /// Creates the wiring over the engine database and secret store.
  ///
  /// [dataDir] holds the short-lived files for keystores (`tmp/credentials`).
  /// `githubBaseUrl` replaces GitHub in tests.
  new({
    required SqliteDatabase database,
    required SecretStore secrets,
    required ProjectRepository projects,
    required ProcessRunner runner,
    required OutputMasker masker,
    required EventLog events,
    required Clock clock,
    required AppleStores apple,
    required PlayStores play,
    required FirebaseStores firebase,
    required String dataDir,
    required bool isMacOS,
    Duration healthInterval = const Duration(hours: 24),
    Uri? githubBaseUrl,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : repository = SqliteCredentialRepository(database),
       temporaryFiles = DirectoryTemporaryFileStore(
         p.join(dataDir, 'tmp', 'credentials'),
       ),
       _github = HttpGitHubTokenVerifier(baseUrl: githubBaseUrl) {
    service = CredentialService(
      repository: repository,
      projects: projects,
      secrets: secrets,
      verifiers: [
        AscKeyVerifier(apple.connect),
        AppleIdVerifier(runner: runner, isMacOS: isMacOS),
        PlayServiceAccountVerifier(play.connect),
        FirebaseServiceAccountVerifier(firebase.connect),
        KeystoreVerifier(runner: runner, files: temporaryFiles),
        ShorebirdCliVerifier(ShorebirdCli(runner: runner)),
        _github,
        const SlackWebhookVerifier(),
      ],
      masker: masker,
      events: events,
      clock: clock,
    );
    health = CredentialHealthCheck(
      service: service,
      repository: repository,
      clock: clock,
      interval: healthInterval,
      onError: onError,
    );
  }

  /// Where credential references are kept.
  final CredentialRepository repository;

  /// Short-lived files for secrets.
  final DirectoryTemporaryFileStore temporaryFiles;

  final HttpGitHubTokenVerifier _github;

  /// Saves, checks and removes credentials.
  late final CredentialService service;

  /// Checks every credential once a day.
  late final CredentialHealthCheck health;

  /// The `credentials` guard check.
  GuardCheck get guardCheck => CredentialsCheck(repository);

  /// Stops the health check and releases the HTTP client.
  void close() {
    health.stop();
    _github.close();
  }
}
