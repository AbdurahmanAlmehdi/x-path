import 'dart:async';
import 'dart:convert';

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
  const new({
    required this._runner,
    required this._secrets,
    this.executable = 'shorebird',
    this.timeout = const Duration(minutes: 2),
  });

  /// The Shorebird CLI.
  final String executable;

  /// How long the CLI has to answer.
  final Duration timeout;

  final ProcessRunner _runner;
  final SecretStore _secrets;

  /// The releases, or `null` if the CLI is missing, too slow, fails, or says
  /// something that is not the documented JSON, or the API key cannot be
  /// read.
  @override
  Future<List<ShorebirdRelease>?> releases(
    String appId, {
    String? tokenSecret,
  }) async {
    final environment = <String, String>{'CI': 'true'};
    if (tokenSecret != null) {
      final String? token;
      try {
        token = await _secrets.read(tokenSecret);
      } on SecretStoreException {
        return null;
      }
      if (token == null) return null;
      environment['SHOREBIRD_TOKEN'] = token;
    }
    final ProcessOutput output;
    try {
      output = await _runner.run(
        executable,
        ['--json', 'releases', 'list', '--app-id', appId],
        environment: environment,
        timeout: timeout,
      );
    } on ProcessStartException {
      return null;
    } on TimeoutException {
      return null;
    }
    if (output.exitCode != 0) return null;
    return _parse(output.stdout);
  }

  static List<ShorebirdRelease>? _parse(String stdout) {
    final Object? json;
    try {
      json = jsonDecode(stdout);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic> || json['status'] != 'success') {
      return null;
    }
    final data = json['data'];
    final listed = data is Map<String, dynamic> ? data['releases'] : null;
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
