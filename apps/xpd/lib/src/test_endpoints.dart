/// Environment variables that point the engine at fake servers, for the
/// end-to-end scripts (`tool/e2e/release_e2e.sh`). They are for tests only:
/// never set them on an engine that releases real apps. `xpd serve` says so
/// when one is set.
class TestEndpoints {
  /// Creates the settings.
  const new({
    this.githubApiUrl,
    this.firebaseUrl,
    this.ascUrl,
    this.playUrl,
    this.fileSecrets = false,
    this.leaseSeconds,
    this.ascUploadSeconds,
  });

  /// Reads the settings from [environment].
  factory fromEnvironment(Map<String, String> environment) {
    Uri? url(String name) {
      final text = environment[name];
      return text == null || text.isEmpty ? null : Uri.parse(text);
    }

    return TestEndpoints(
      githubApiUrl: url(githubApiVariable),
      firebaseUrl: url(firebaseVariable),
      ascUrl: url(ascVariable),
      playUrl: url(playVariable),
      fileSecrets: environment[fileSecretsVariable] == '1',
      leaseSeconds: int.tryParse(environment[leaseSecondsVariable] ?? ''),
      ascUploadSeconds: int.tryParse(
        environment[ascUploadSecondsVariable] ?? '',
      ),
    );
  }

  /// The GitHub REST API a fake serves instead of `api.github.com`.
  static const githubApiVariable = 'XPD_TEST_GITHUB_API_URL';

  /// The Firebase App Distribution API a fake serves.
  static const firebaseVariable = 'XPD_TEST_FIREBASE_URL';

  /// The App Store Connect API a fake serves. The fake serves the iTunes
  /// lookup (`/lookup`) on the same address, so this one points both there.
  static const ascVariable = 'XPD_TEST_ASC_URL';

  /// The Google Play Developer API a fake serves, for the API and for the
  /// uploads.
  static const playVariable = 'XPD_TEST_PLAY_URL';

  /// `1` keeps every secret in the encrypted file of the data directory, as
  /// on Linux, instead of the Keychain of the Mac.
  static const fileSecretsVariable = 'XPD_TEST_FILE_SECRETS';

  /// How long a runner's lease lasts, in seconds, instead of 90: the runner
  /// offline end-to-end test waits out a few leases in seconds.
  static const leaseSecondsVariable = 'XPD_TEST_LEASE_SECONDS';

  /// How long `upload.appStore` waits for App Store Connect to accept or
  /// refuse a build upload, in seconds, polling every second, instead of 30
  /// minutes: the release end-to-end test waits out a stalled upload.
  static const ascUploadSecondsVariable = 'XPD_TEST_ASC_UPLOAD_SECONDS';

  /// Where GitHub is, when it is not GitHub.
  final Uri? githubApiUrl;

  /// Where Firebase is, when it is not Google.
  final Uri? firebaseUrl;

  /// Where App Store Connect and the iTunes lookup are, when they are not
  /// Apple.
  final Uri? ascUrl;

  /// Where Google Play is, when it is not Google.
  final Uri? playUrl;

  /// Whether secrets go to the encrypted file even on macOS.
  final bool fileSecrets;

  /// How long a runner's lease lasts, when it is not the usual 90 seconds.
  final int? leaseSeconds;

  /// How long a build upload may take, when it is not the usual 30 minutes.
  final int? ascUploadSeconds;

  /// Whether anything differs from a real engine.
  bool get isActive =>
      githubApiUrl != null ||
      firebaseUrl != null ||
      ascUrl != null ||
      playUrl != null ||
      fileSecrets ||
      leaseSeconds != null ||
      ascUploadSeconds != null;

  /// The operating system the secret store is chosen for.
  String secretStoreSystem(String operatingSystem) =>
      fileSecrets ? 'linux' : operatingSystem;
}
