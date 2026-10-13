import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Where the checked-in schema of each version lives: `v<version>.sql`.
final snapshotDirectory = Directory('test/src/sqlite/snapshots');

/// The statements that create [connection]'s schema, tables first, each
/// followed by a semicolon. Executing the dump on an empty database builds the
/// same schema, so a golden file is also a loadable snapshot.
String dumpSchema(Database connection) {
  final rows = connection.select(
    'SELECT sql FROM sqlite_schema '
    "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
    "ORDER BY type != 'table', name",
  );
  return '${rows.map((row) => '${row['sql']};').join('\n\n')}\n';
}

/// The golden schema file of [version].
File snapshotFile(int version) =>
    File('${snapshotDirectory.path}/v$version.sql');

/// The versions that have a golden file, ascending.
List<int> snapshotVersions() =>
    snapshotDirectory
        .listSync()
        .map((entity) => RegExp(r'v(\d+)\.sql$').firstMatch(entity.path))
        .whereType<RegExpMatch>()
        .map((match) => int.parse(match.group(1)!))
        .toList()
      ..sort();

/// A temporary directory that is deleted when the test ends.
Directory tempDirectory() {
  final directory = Directory.systemTemp.createTempSync('xp_adapters_');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
