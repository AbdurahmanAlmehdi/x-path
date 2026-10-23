import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Projects in the `project` table.
///
/// A project row keeps the raw scan and the owner's edits as JSON. The `app`
/// and `flavor` rows are the effective profile (scan with edits) written out
/// each time a project is stored: they carry the ids, build counters and
/// credential references that later phases attach to. A rescan keeps the id
/// and counter of an app that is still there, and never deletes an app that
/// has releases.
class SqliteProjectRepository implements ProjectRepository {
  /// Creates a repository over a database.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new(this._database, {Random? random}) : _random = random ?? Random.secure();

  static const _sqliteConstraintForeignKey = 787;

  final SqliteDatabase _database;
  final Random _random;

  Database get _db => _database.connection;

  static const _columns =
      'id, github_repo_id, full_name, remote, github_default_branch, '
      'local_path, scan, findings, scanned_at, edits';

  @override
  Future<List<ProjectRecord>> list() async => [
    for (final row in _db.select(
      'SELECT $_columns FROM project ORDER BY rowid',
    ))
      _fromRow(row),
  ];

  @override
  Future<ProjectRecord?> get(String id) async =>
      _one(_db.select('SELECT $_columns FROM project WHERE id = ?', [id]));

  @override
  Future<ProjectRecord?> findByGithubRepoId(int githubRepoId) async => _one(
    _db.select('SELECT $_columns FROM project WHERE github_repo_id = ?', [
      githubRepoId,
    ]),
  );

  @override
  Future<void> add(ProjectRecord record) async {
    _database.transaction(() {
      _db.execute(
        'INSERT INTO project (id, github_repo_id, remote, '
        'default_base_branch, full_name, github_default_branch, local_path, '
        'scan, findings, scanned_at, edits) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        _values(record, includeIdentity: true),
      );
      _writeProfile(record);
    });
  }

  @override
  Future<void> update(ProjectRecord record) async {
    _database.transaction(() {
      _db.execute(
        'UPDATE project SET github_repo_id = ?, remote = ?, '
        'default_base_branch = ?, full_name = ?, github_default_branch = ?, '
        'local_path = ?, scan = ?, findings = ?, scanned_at = ?, edits = ? '
        'WHERE id = ?',
        [..._values(record, includeIdentity: false), record.id],
      );
      if (_db.updatedRows == 0) {
        throw StateError('There is no project ${record.id}.');
      }
      _writeProfile(record);
    });
  }

  @override
  Future<bool> remove(String id) async {
    try {
      _db.execute('DELETE FROM project WHERE id = ?', [id]);
    } on SqliteException catch (error) {
      if (error.extendedResultCode == _sqliteConstraintForeignKey) {
        throw ProjectInUseException(id);
      }
      rethrow;
    }
    return _db.updatedRows > 0;
  }

  // ------------------------------------------------------------ project row

  ProjectRecord? _one(ResultSet rows) =>
      rows.isEmpty ? null : _fromRow(rows.single);

  /// The values of the insert (with the id first) or update statements.
  List<Object?> _values(
    ProjectRecord record, {
    required bool includeIdentity,
  }) => [
    if (includeIdentity) record.id,
    record.githubRepoId,
    record.remote,
    record.defaultBaseBranch,
    record.fullName,
    record.githubDefaultBranch,
    record.localPath,
    jsonEncode(record.scan.toJson()),
    jsonEncode([for (final finding in record.findings) finding.toJson()]),
    toDatabaseTime(record.scannedAt),
    jsonEncode(record.edits.toJson()),
  ];

  static ProjectRecord _fromRow(Row row) => ProjectRecord(
    id: row['id'] as String,
    githubRepoId: row['github_repo_id'] as int,
    fullName: row['full_name'] as String,
    remote: row['remote'] as String,
    githubDefaultBranch: row['github_default_branch'] as String,
    localPath: row['local_path'] as String?,
    scan: ProjectProfile.fromJson(
      jsonDecode(row['scan'] as String) as Map<String, dynamic>,
    ),
    findings: [
      for (final finding in jsonDecode(row['findings'] as String) as List)
        Finding.fromJson(finding as Map<String, dynamic>),
    ],
    scannedAt: fromDatabaseTime(row['scanned_at'] as int),
    edits: ProfileEdits.fromJson(
      jsonDecode(row['edits'] as String) as Map<String, dynamic>,
    ),
  );

  // ------------------------------------------------------- app and flavors

  /// Rewrites the app and flavor rows of [record] from its effective profile.
  void _writeProfile(ProjectRecord record) {
    final apps = record.profile.apps;
    final existingApps = {
      for (final row in _db.select(
        'SELECT id, path FROM app WHERE project_id = ?',
        [record.id],
      ))
        row['path'] as String: row['id'] as String,
    };
    for (final app in apps) {
      final appId = existingApps[app.path] ?? _newId('app');
      _db.execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT (id) DO UPDATE SET framework = excluded.framework, '
        'store_country = excluded.store_country',
        [appId, record.id, app.path, app.framework, app.storeCountry],
      );
      _writeFlavors(appId, app);
    }
    // History is never deleted by cascade: an app with releases stays.
    final kept = [for (final app in apps) app.path];
    _db.execute(
      'DELETE FROM app WHERE project_id = ? '
      'AND path NOT IN (${_placeholders(kept.length)}) '
      'AND id NOT IN (SELECT app_id FROM release)',
      [record.id, ...kept],
    );
  }

  void _writeFlavors(String appId, AppProfile app) {
    final existing = {
      for (final row in _db.select(
        'SELECT id, name FROM flavor WHERE app_id = ?',
        [appId],
      ))
        row['name'] as String: row['id'] as String,
    };
    for (final flavor in app.flavors) {
      _db.execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id, '
        'android_app_id, shorebird, prod, version_files, '
        'firebase_app_id_android, firebase_app_id_ios, apple_app_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (id) DO UPDATE SET entrypoint = excluded.entrypoint, '
        'ios_bundle_id = excluded.ios_bundle_id, '
        'android_app_id = excluded.android_app_id, '
        'shorebird = excluded.shorebird, prod = excluded.prod, '
        'version_files = excluded.version_files, '
        'firebase_app_id_android = excluded.firebase_app_id_android, '
        'firebase_app_id_ios = excluded.firebase_app_id_ios, '
        'apple_app_id = excluded.apple_app_id',
        [
          existing[flavor.name] ?? _newId('flv'),
          appId,
          flavor.name,
          flavor.entrypoint,
          flavor.iosBundleId,
          flavor.androidAppId,
          if (flavor.shorebird) 1 else 0,
          if (flavor.prod) 1 else 0,
          jsonEncode(flavor.versionFiles),
          flavor.firebaseAppId?['android'],
          flavor.firebaseAppId?['ios'],
          flavor.appleAppId,
        ],
      );
    }
    final kept = [for (final flavor in app.flavors) flavor.name];
    _db.execute(
      'DELETE FROM flavor WHERE app_id = ? '
      'AND name NOT IN (${_placeholders(kept.length)})',
      [appId, ...kept],
    );
  }

  String _placeholders(int count) => List.filled(count, '?').join(', ');

  String _newId(String prefix) {
    final bytes = List.generate(8, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${prefix}_$hex';
  }
}
