import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// Runners in the `runner` table. `capabilities` is a JSON array of the wire
/// names the engine found with its probe.
class SqliteRunnerRepository implements RunnerRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _columns =
      'id, name, token_id, capabilities, slots, os, arch, version, cores, '
      'last_heartbeat, created_at, revoked_at';

  @override
  Future<void> add(RunnerRecord runner) async {
    _db.execute(
      'INSERT INTO runner ($_columns) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      _values(runner),
    );
  }

  @override
  Future<RunnerRecord?> get(String id) => _one('id', id);

  @override
  Future<RunnerRecord?> findByName(String name) => _one('name', name);

  @override
  Future<RunnerRecord?> findByToken(String tokenId) =>
      _one('token_id', tokenId);

  @override
  Future<List<RunnerRecord>> list() async => [
    for (final row in _db.select('SELECT $_columns FROM runner ORDER BY rowid'))
      _fromRow(row),
  ];

  @override
  Future<void> update(RunnerRecord runner) async {
    final values = _values(runner);
    _db.execute(
      'UPDATE runner SET name = ?, token_id = ?, capabilities = ?, '
      'slots = ?, os = ?, arch = ?, version = ?, cores = ?, '
      'last_heartbeat = ?, created_at = ?, revoked_at = ? WHERE id = ?',
      [...values.skip(1), runner.id],
    );
    if (_db.updatedRows == 0) {
      throw StateError('There is no runner ${runner.id}.');
    }
  }

  Future<RunnerRecord?> _one(String column, String value) async {
    final rows = _db.select('SELECT $_columns FROM runner WHERE $column = ?', [
      value,
    ]);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  /// The values in the order of [_columns].
  static List<Object?> _values(RunnerRecord runner) => [
    runner.id,
    runner.name,
    runner.tokenId,
    jsonEncode(RunnerRecord.wireNames(runner.capabilities)),
    runner.slots,
    runner.os,
    runner.arch,
    runner.version,
    runner.cores,
    _time(runner.lastHeartbeat),
    toDatabaseTime(runner.createdAt),
    _time(runner.revokedAt),
  ];

  static int? _time(DateTime? time) =>
      time == null ? null : toDatabaseTime(time);

  static DateTime? _fromTime(Object? value) =>
      value == null ? null : fromDatabaseTime(value as int);

  static RunnerRecord _fromRow(Row row) => RunnerRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    tokenId: row['token_id'] as String,
    capabilities: _capabilities(row['capabilities'] as String),
    slots: row['slots'] as int,
    os: row['os'] as String?,
    arch: row['arch'] as String?,
    version: row['version'] as String?,
    cores: row['cores'] as int?,
    lastHeartbeat: _fromTime(row['last_heartbeat']),
    createdAt: fromDatabaseTime(row['created_at'] as int),
    revokedAt: _fromTime(row['revoked_at']),
  );

  /// The capabilities in the JSON array. A value that is not an array (the
  /// `{}` a row of the first schema has) or a name this engine does not know
  /// counts for nothing.
  static Set<Capability> _capabilities(String json) {
    final decoded = jsonDecode(json);
    return {
      if (decoded is List<dynamic>)
        for (final name in decoded)
          if (name is String) ?Capability.fromWire(name),
    };
  }
}
