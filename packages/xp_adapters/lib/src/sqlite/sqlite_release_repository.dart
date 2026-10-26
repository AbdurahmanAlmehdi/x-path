import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Releases in the `release` table (D-17).
///
/// The table keeps the app by its row id; the project and the path of the app
/// are read through it. The status in each store, and the builds, are JSON
/// columns.
class SqliteReleaseRepository implements ReleaseRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _select =
      'SELECT r.id, a.project_id, a.path AS app_path, r.flavor, r.version, '
      'r.build, r.state, r.store_status, r.builds, r.base_branch, r.branch, '
      'r.tag, r.head_sha, r.pr_number, r.pr_url, r.merge_sha, '
      'r.merge_run_id, r.message, r.whats_new, r.what_to_test, r.created_at, '
      'r.updated_at '
      'FROM release r JOIN app a ON a.id = r.app_id';

  @override
  Future<ReleaseRecord?> get(String id) async {
    final rows = _db.select('$_select WHERE r.id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<ReleaseRecord>> list({
    String? projectId,
    String? appPath,
    Set<ReleaseState>? states,
  }) async {
    final wanted = states?.toList();
    return [
      for (final row in _db.select(
        '$_select WHERE (?1 IS NULL OR a.project_id = ?1) '
        'AND (?2 IS NULL OR a.path = ?2) '
        '${wanted == null ? '' : 'AND r.state IN '
                  '(${List.filled(wanted.length, '?').join(', ')}) '}'
        'ORDER BY r.created_at DESC, r.rowid DESC',
        [projectId, appPath, ...?wanted?.map((state) => state.wire)],
      ))
        _fromRow(row),
    ];
  }

  @override
  Future<void> create(ReleaseRecord release) async {
    _db.execute(
      'INSERT INTO release (id, app_id, version, build, state, tag, pr_url, '
      'store_status, flavor, base_branch, branch, head_sha, pr_number, '
      'merge_sha, merge_run_id, message, builds, whats_new, what_to_test, '
      'created_at, updated_at) '
      'VALUES (?, (SELECT id FROM app WHERE project_id = ? AND path = ?), '
      '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        release.id,
        release.projectId,
        release.appPath,
        release.version,
        release.build,
        release.state.wire,
        release.tag,
        release.prUrl,
        jsonEncode(release.storesToJson()),
        release.flavor,
        release.baseBranch,
        release.branch,
        release.headSha,
        release.prNumber,
        release.mergeCommit,
        release.mergeRunId,
        release.message,
        jsonEncode([for (final build in release.builds) build.toJson()]),
        release.whatsNew,
        release.whatToTest,
        toDatabaseTime(release.createdAt),
        toDatabaseTime(release.updatedAt),
      ],
    );
  }

  @override
  Future<void> update(ReleaseRecord release) async {
    _db.execute(
      'UPDATE release SET build = ?, state = ?, tag = ?, pr_url = ?, '
      'store_status = ?, branch = ?, head_sha = ?, pr_number = ?, '
      'merge_sha = ?, merge_run_id = ?, message = ?, builds = ?, '
      'whats_new = ?, what_to_test = ?, updated_at = ? WHERE id = ?',
      [
        release.build,
        release.state.wire,
        release.tag,
        release.prUrl,
        jsonEncode(release.storesToJson()),
        release.branch,
        release.headSha,
        release.prNumber,
        release.mergeCommit,
        release.mergeRunId,
        release.message,
        jsonEncode([for (final build in release.builds) build.toJson()]),
        release.whatsNew,
        release.whatToTest,
        toDatabaseTime(release.updatedAt),
        release.id,
      ],
    );
  }

  @override
  Future<void> addEvent(String releaseId, ReleaseEvent event) async {
    _db.execute(
      'INSERT INTO release_event (release_id, kind, at, store, detail, '
      'by_name, run_id, patch_number) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        releaseId,
        event.kind.wire,
        toDatabaseTime(event.at),
        event.store?.wire,
        event.detail,
        event.by,
        event.runId,
        event.patchNumber,
      ],
    );
  }

  @override
  Future<List<ReleaseEvent>> events(String releaseId) async => [
    for (final row in _db.select(
      'SELECT kind, at, store, detail, by_name, run_id, patch_number '
      'FROM release_event WHERE release_id = ? ORDER BY at, id',
      [releaseId],
    ))
      ReleaseEvent(
        kind: ReleaseEventKind.values.firstWhere((k) => k.wire == row['kind']),
        at: fromDatabaseTime(row['at'] as int),
        store: switch (row['store']) {
          final String wire => ReleaseStore.values.firstWhere(
            (store) => store.wire == wire,
          ),
          _ => null,
        },
        detail: row['detail'] as String?,
        by: row['by_name'] as String?,
        runId: row['run_id'] as String?,
        patchNumber: row['patch_number'] as int?,
      ),
  ];

  static ReleaseRecord _fromRow(Row row) => ReleaseRecord(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    appPath: row['app_path'] as String,
    flavor: row['flavor'] as String,
    version: row['version'] as String,
    build: row['build'] as int,
    state: ReleaseState.values.firstWhere((s) => s.wire == row['state']),
    stores: ReleaseRecord.storesFromJson(
      jsonDecode(row['store_status'] as String) as Map<String, dynamic>,
    ),
    builds: [
      for (final build in jsonDecode(row['builds'] as String) as List)
        ReleaseBuild.fromJson(build as Map<String, dynamic>),
    ],
    baseBranch: row['base_branch'] as String,
    branch: row['branch'] as String?,
    tag: row['tag'] as String?,
    headSha: row['head_sha'] as String?,
    prNumber: row['pr_number'] as int?,
    prUrl: row['pr_url'] as String?,
    mergeCommit: row['merge_sha'] as String?,
    mergeRunId: row['merge_run_id'] as String?,
    message: row['message'] as String?,
    whatsNew: row['whats_new'] as String?,
    whatToTest: row['what_to_test'] as String?,
    createdAt: fromDatabaseTime(row['created_at'] as int),
    updatedAt: fromDatabaseTime(row['updated_at'] as int),
  );
}
