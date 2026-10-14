import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xp/src/version.dart';

/// Set to any non-empty value to turn the update check off.
const noUpdateCheckVariable = 'XP_NO_UPDATE_CHECK';

/// Looks for a release newer than this `xp`.
abstract interface class UpdateCheck {
  /// The check for the real process: off when `XP_NO_UPDATE_CHECK` is set.
  factory system(String configDir, Map<String, String> environment) {
    if ((environment[noUpdateCheckVariable] ?? '').isNotEmpty) {
      return const NoUpdateCheck();
    }
    return GitHubUpdateCheck(
      cacheFile: File(p.join(configDir, 'update-check.json')),
    );
  }

  /// The version of the newest release, if it is newer than this one.
  ///
  /// Never throws and never takes longer than the check's own timeout: any
  /// failure (offline, a private repository, a rate limit) is no news.
  Future<String?> newerVersion();
}

/// A check that finds nothing, because it is off.
class NoUpdateCheck implements UpdateCheck {
  /// Creates the check.
  const new();

  @override
  Future<String?> newerVersion() async => null;
}

/// Compares this `xp` with the latest release of the XPath repository on
/// GitHub (`AbdurahmanAlmehdi/x-path`).
///
/// What it sends (D-24: no telemetry): one unauthenticated `GET` of the
/// public release list with a fixed `User-Agent`. No version of this program,
/// no machine, no user, no engine address. The answer is cached for a day in
/// `update-check.json` in the config folder, so most commands make no request
/// at all. The repository is private until 1.0, so the lookup fails (404)
/// silently until then.
class GitHubUpdateCheck implements UpdateCheck {
  /// Creates the check. `client`, `now` and `currentVersion` are for tests.
  new({
    required this.cacheFile,
    this._client,
    DateTime Function()? now,
    this.currentVersion = packageVersion,
    this.timeout = const Duration(seconds: 2),
    this.maxAge = const Duration(days: 1),
  }) : _now = now ?? DateTime.now;

  /// The release lookup.
  static final Uri latestRelease = Uri.parse(
    'https://api.github.com/repos/AbdurahmanAlmehdi/x-path/releases/latest',
  );

  /// Where the last answer is kept.
  final File cacheFile;

  /// The version of this program.
  final String currentVersion;

  /// How long to wait for GitHub.
  final Duration timeout;

  /// How long an answer is good for.
  final Duration maxAge;

  final http.Client? _client;
  final DateTime Function() _now;

  @override
  Future<String?> newerVersion() async {
    try {
      final latest = await _latest();
      return latest != null && isNewerVersion(latest, currentVersion)
          ? latest
          : null;
    } on Object {
      return null;
    }
  }

  Future<String?> _latest() async {
    final cached = _readCache();
    if (cached != null && _now().difference(cached.checkedAt) < maxAge) {
      return cached.latest;
    }
    final latest = await _fetch();
    _writeCache(latest);
    return latest;
  }

  Future<String?> _fetch() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            latestRelease,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'xp-update-check',
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final tag =
          (jsonDecode(response.body) as Map<String, dynamic>)['tag_name'];
      return tag is String ? tag.replaceFirst(RegExp('^v'), '') : null;
    } on Object {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  ({DateTime checkedAt, String? latest})? _readCache() {
    try {
      final json = jsonDecode(cacheFile.readAsStringSync());
      return (
        checkedAt: DateTime.parse(
          (json as Map<String, dynamic>)['checkedAt'] as String,
        ),
        latest: json['latest'] as String?,
      );
    } on Object {
      return null;
    }
  }

  void _writeCache(String? latest) {
    try {
      cacheFile.parent.createSync(recursive: true);
      cacheFile.writeAsStringSync(
        jsonEncode({
          'checkedAt': _now().toUtc().toIso8601String(),
          'latest': latest,
        }),
      );
    } on Object {
      // A cache that cannot be written only means one more lookup later.
    }
  }
}

/// Whether version [candidate] (`1.2.3`, a leading `v` allowed) is newer than
/// [current]. A pre-release (`1.2.3-rc.1`) or anything that is not
/// `major.minor.patch` is never newer.
bool isNewerVersion(String candidate, String current) {
  final a = _parse(candidate);
  final b = _parse(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

List<int>? _parse(String version) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(version.trim());
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}
