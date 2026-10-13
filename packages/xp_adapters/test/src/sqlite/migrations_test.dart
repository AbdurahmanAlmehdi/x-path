import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

import '../../helpers/schema_dump.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite the golden file of every version from
/// the migrations. Review the diff: a released golden must never change.
final _update = Platform.environment['UPDATE_GOLDENS'] == '1';

String _golden(int version) => snapshotFile(version).readAsStringSync();

void main() {
  final latest = engineMigrations.length;

  setUpAll(() {
    if (!_update) return;
    for (final migration in engineMigrations) {
      final database = SqliteDatabase.openInMemory(
        migrations: engineMigrations.take(migration.version).toList(),
      );
      snapshotFile(migration.version)
          .writeAsStringSync(dumpSchema(database.connection));
      database.close();
    }
  });

  group('engineMigrations', () {
    test('count up from 1', () {
      expect(
        engineMigrations.map((migration) => migration.version),
        List.generate(latest, (i) => i + 1),
      );
    });

    test('have exactly one golden schema each', () {
      expect(snapshotVersions(), List.generate(latest, (i) => i + 1));
    });

    test('are all valid SQL that runs in order', () {
      final database = SqliteDatabase.openInMemory();
      addTearDown(database.close);

      expect(database.connection.userVersion, latest);
    });
  });

  group('snapshot', () {
    for (var version = 1; version <= latest; version++) {
      test('v$version is what the first $version migration(s) build', () {
        final database = SqliteDatabase.openInMemory(
          migrations: engineMigrations.take(version).toList(),
        );
        addTearDown(database.close);

        expect(dumpSchema(database.connection), _golden(version));
        expect(database.connection.userVersion, version);
      });
    }

    test('migrating from an empty database reaches the latest golden', () {
      final directory = tempDirectory();

      final database = SqliteDatabase.open('${directory.path}/xpath.db');
      addTearDown(database.close);

      expect(dumpSchema(database.connection), _golden(latest));
      expect(database.connection.userVersion, latest);
    });

    for (var version = 1; version <= latest; version++) {
      test(
        'migrating from the v$version snapshot reaches the latest golden',
        () {
          final path = '${tempDirectory().path}/xpath.db';
          sqlite3.open(path)
            ..execute(_golden(version))
            ..userVersion = version
            ..close();

          final database = SqliteDatabase.open(path);
          addTearDown(database.close);

          expect(dumpSchema(database.connection), _golden(latest));
          expect(database.connection.userVersion, latest);
          expect(
            File('$path.bak-v$version').existsSync(),
            version < latest,
            reason: 'only a database that is migrated is backed up',
          );
        },
      );
    }
  });
}
