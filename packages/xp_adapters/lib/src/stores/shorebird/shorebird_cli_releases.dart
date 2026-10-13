import 'package:xp_adapters/src/stores/shorebird/shorebird_cli.dart';
import 'package:xp_engine/xp_engine.dart';

/// The releases of a Shorebird app, read with `shorebird --json releases
/// list`.
///
/// The CLI answers one JSON object, `{"status": "success", "data":
/// {"releases": [...]}}`. A release has `version`, `flutter_version` (absent
/// for releases of old CLI versions) and `platform_statuses`, which maps a
/// platform to `draft` or `active`. The API key is read from the secret store
/// and handed to the CLI in `SHOREBIRD_TOKEN`, never as an argument.
class ShorebirdCliReleases implements ShorebirdReleases {
  /// Creates the adapter. The CLI is [executable]; it has [timeout] to answer.
  new({
    required ProcessRunner runner,
    required this._secrets,
    String executable = 'shorebird',
    Duration timeout = const Duration(minutes: 2),
  }) : _cli = ShorebirdCli(
         runner: runner,
         executable: executable,
         timeout: timeout,
       );

  final ShorebirdCli _cli;
  final SecretStore _secrets;

  /// The releases, or `null` if the CLI is missing, too slow, fails, or says
  /// something that is not the documented JSON, or the API key cannot be
  /// read.
  @override
  Future<List<ShorebirdRelease>?> releases(
    String appId, {
    String? tokenSecret,
  }) async {
    String? token;
    if (tokenSecret != null) {
      try {
        token = await _secrets.read(tokenSecret);
      } on SecretStoreException {
        return null;
      }
      if (token == null) return null;
    }
    final result = await _cli.run([
      '--json',
      'releases',
      'list',
      '--app-id',
      appId,
    ], token: token);
    if (result is! ShorebirdCliSuccess) return null;
    final listed = result.data['releases'];
    if (listed is! List) return null;
    return [
      for (final entry in listed)
        if (entry is Map<String, dynamic>) ?_release(entry),
    ];
  }

  static ShorebirdRelease? _release(Map<String, dynamic> entry) {
    final version = entry['version'];
    if (version is! String) return null;
    final AppVersion parsed;
    try {
      parsed = AppVersion.parse(version);
    } on FormatException {
      return null;
    }
    final flutter = entry['flutter_version'];
    final statuses = entry['platform_statuses'];
    return ShorebirdRelease(
      version: parsed,
      flutterVersion: flutter is String ? flutter : null,
      activePlatforms: {
        if (statuses is Map<String, dynamic>)
          for (final status in statuses.entries)
            if (status.value == 'active') status.key,
      },
    );
  }
}
