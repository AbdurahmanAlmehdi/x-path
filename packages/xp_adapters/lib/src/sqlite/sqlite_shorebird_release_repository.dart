import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// The Flutter versions of Shorebird releases, in the `shorebird_release`
/// table.
class SqliteShorebirdReleaseRepository implements ShorebirdReleaseRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  @override
  Future<void> save(ShorebirdReleaseRecord record) async {
    _db.execute(
      'INSERT INTO shorebird_release (app_id, version, platform, '
      'flutter_version, job_id, recorded_at) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (app_id, version, platform) DO UPDATE SET '
      'flutter_version = excluded.flutter_version, '
      'job_id = excluded.job_id, recorded_at = excluded.recorded_at',
      [
        record.appId,
        '${record.version}',
        record.platform.wire,
        record.flutterVersion,
        record.jobId,
        toDatabaseTime(record.recordedAt),
      ],
    );
  }

  @override
  Future<Set<String>> flutterVersions() async => {
    for (final row in _db.select(
      'SELECT DISTINCT flutter_version FROM shorebird_release',
    ))
      row['flutter_version'] as String,
  };

  @override
  Future<ShorebirdReleaseRecord?> find(
    String appId,
    AppVersion version,
    ShorebirdPlatform platform,
  ) async {
    final rows = _db.select(
      'SELECT flutter_version, job_id, recorded_at FROM shorebird_release '
      'WHERE app_id = ? AND version = ? AND platform = ?',
      [appId, '$version', platform.wire],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ShorebirdReleaseRecord(
      appId: appId,
      version: version,
      platform: platform,
      flutterVersion: row['flutter_version'] as String,
      jobId: row['job_id'] as String,
      recordedAt: fromDatabaseTime(row['recorded_at'] as int),
    );
  }
}
