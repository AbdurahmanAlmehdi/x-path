import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 11, 14, 9, 30, 15, 123, 456);

void main() {
  late SqliteDatabase database;
  late SqliteSignInCodeRepository repository;
  late String owner;

  SignInCodeRecord code(String hash, {String? personId, DateTime? usedAt}) =>
      SignInCodeRecord(
        hash: hash,
        personId: personId ?? owner,
        createdAt: _created,
        expiresAt: _created.add(const Duration(minutes: 10)),
        usedAt: usedAt,
      );

  List<Map<String, Object?>> rows() => [
    for (final row in database.connection.select(
      'SELECT * FROM sign_in_code ORDER BY rowid',
    ))
      {...row},
  ];

  setUp(() async {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteSignInCodeRepository(database);
    owner = (await SqlitePersonRepository(database).list()).single.id;
  });

  test('stores only the hash, with the person and the times', () async {
    await repository.add(code('h1'));

    expect(rows(), [
      {
        'hash': 'h1',
        'person_id': owner,
        'created_at': _created.microsecondsSinceEpoch,
        'expires_at': _created
            .add(const Duration(minutes: 10))
            .microsecondsSinceEpoch,
        'used_at': null,
      },
    ]);
  });

  test('uses a code once, while it has not expired', () async {
    await repository.add(code('h1'));
    await repository.add(code('h2'));
    final at = _created.add(const Duration(minutes: 9));

    expect(await repository.use('h1', at: at), owner);
    expect(await repository.use('h1', at: at), isNull);
    expect(await repository.use('nope', at: at), isNull);
    expect(
      await repository.use('h2', at: _created.add(const Duration(minutes: 10))),
      isNull,
    );
    expect(rows().first['used_at'], at.microsecondsSinceEpoch);
    expect(rows().last['used_at'], isNull);
  });

  test("deletes the person's unused codes and the expired ones", () async {
    final people = SqlitePersonRepository(database);
    await people.add(
      Person(
        id: 'per_sam',
        name: 'Sam',
        role: PersonRole.viewer,
        createdAt: _created,
      ),
    );
    await repository.add(code('unused'));
    await repository.add(code('used', usedAt: _created));
    await repository.add(code('other', personId: 'per_sam'));

    await repository.deleteUnusedOf(owner);
    expect(rows().map((row) => row['hash']), ['used', 'other']);

    await repository.deleteExpired(before: _created);
    expect(rows().map((row) => row['hash']), ['used', 'other']);

    await repository.deleteExpired(
      before: _created.add(const Duration(minutes: 11)),
    );
    expect(rows(), isEmpty);
  });

  test(
    'refuses a code of an unknown person or a second one with the hash',
    () async {
      await repository.add(code('h1'));

      await expectLater(
        repository.add(code('h1')),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        repository.add(code('h2', personId: 'per_nope')),
        throwsA(isA<SqliteException>()),
      );
    },
  );
}
