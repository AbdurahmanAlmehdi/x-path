/// Environment variables that point the engine at fake servers, for the
/// end-to-end scripts (`tool/e2e/release_e2e.sh`). They are for tests only:
/// never set them on an engine that releases real apps. `xpd serve` says so
/// when one is set.
class TestEndpoints {
  /// Creates the settings.
  const new({this.githubApiUrl, this.firebaseUrl, this.fileSecrets = false});

  /// Reads the settings from [environment].
  factory fromEnvironment(Map<String, String> environment) {
    Uri? url(String name) {
      final text = environment[name];
      return text == null || text.isEmpty ? null : Uri.parse(text);
    }

    return TestEndpoints(
      githubApiUrl: url(githubApiVariable),
      firebaseUrl: url(firebaseVariable),
      fileSecrets: environment[fileSecretsVariable] == '1',
    );
  }

  /// The GitHub REST API a fake serves instead of `api.github.com`.
  static const githubApiVariable = 'XPD_TEST_GITHUB_API_URL';

  /// The Firebase App Distribution API a fake serves.
  static const firebaseVariable = 'XPD_TEST_FIREBASE_URL';

  /// `1` keeps every secret in the encrypted file of the data directory, as
  /// on Linux, instead of the Keychain of the Mac.
  static const fileSecretsVariable = 'XPD_TEST_FILE_SECRETS';

  /// Where GitHub is, when it is not GitHub.
  final Uri? githubApiUrl;

  /// Where Firebase is, when it is not Google.
  final Uri? firebaseUrl;

  /// Whether secrets go to the encrypted file even on macOS.
  final bool fileSecrets;

  /// Whether anything differs from a real engine.
  bool get isActive =>
      githubApiUrl != null || firebaseUrl != null || fileSecrets;

  /// The operating system the secret store is chosen for.
  String secretStoreSystem(String operatingSystem) =>
      fileSecrets ? 'linux' : operatingSystem;
}
