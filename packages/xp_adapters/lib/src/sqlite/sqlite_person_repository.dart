import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// People in the `person` table (ADR 0017).
class SqlitePersonRepository implements PersonRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  static const _columns = 'id, name, role, created_at, removed_at';

  @override
  Future<List<Person>> list() async => [
    for (final row in _database.connection.select(
      'SELECT $_columns FROM person ORDER BY created_at, rowid',
    ))
      _fromRow(row),
  ];

  @override
  Future<Person?> get(String id) async {
    final rows = _database.connection.select(
      'SELECT $_columns FROM person WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> add(Person person) async => _database.connection.execute(
    'INSERT INTO person ($_columns) VALUES (?, ?, ?, ?, ?)',
    [person.id, ..._values(person)],
  );

  @override
  Future<void> update(Person person) async => _database.connection.execute(
    'UPDATE person SET name = ?, role = ?, created_at = ?, removed_at = ? '
    'WHERE id = ?',
    [..._values(person), person.id],
  );

  static List<Object?> _values(Person person) {
    final removedAt = person.removedAt;
    return [
      person.name,
      person.role.name,
      toDatabaseTime(person.createdAt),
      if (removedAt == null) null else toDatabaseTime(removedAt),
    ];
  }

  static Person _fromRow(Row row) {
    final removedAt = row['removed_at'] as int?;
    return Person(
      id: row['id'] as String,
      name: row['name'] as String,
      role: PersonRole.values.byName(row['role'] as String),
      createdAt: fromDatabaseTime(row['created_at'] as int),
      removedAt: removedAt == null ? null : fromDatabaseTime(removedAt),
    );
  }
}
