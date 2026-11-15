import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  late SqliteDatabase database;
  late SqlitePersonRepository repository;
  final sam = Person(
    id: 'per_sam',
    name: 'Sam',
    role: PersonRole.developer,
    createdAt: DateTime.utc(2100, 1, 2, 8, 30, 15, 123, 456),
  );

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqlitePersonRepository(database);
  });

  test('starts with the admin Owner that migration v23 made', () async {
    final owner = (await repository.list()).single;

    expect(owner.name, 'Owner');
    expect(owner.role, PersonRole.admin);
    expect(owner.isRemoved, isFalse);
    expect(await repository.get(owner.id), owner);
  });

  test('adds a person and reads every field back', () async {
    await repository.add(sam);

    expect(await repository.get('per_sam'), sam);
    expect((await repository.list()).last, sam);
    expect(await repository.get('per_nobody'), isNull);
  });

  test('updates the name, role and removal of a person', () async {
    await repository.add(sam);
    final changed = sam.copyWith(
      name: 'Sam K',
      role: PersonRole.releaser,
      removedAt: DateTime.utc(2026, 11, 14),
    );

    await repository.update(changed);

    expect(await repository.get('per_sam'), changed);
  });

  test('lists people oldest first', () async {
    await repository.add(sam);
    await repository.add(
      Person(
        id: 'per_early',
        name: 'Early',
        role: PersonRole.viewer,
        createdAt: DateTime.utc(2000),
      ),
    );

    expect((await repository.list()).map((p) => p.id).take(1), ['per_early']);
  });

  test('refuses a second active person with the same name', () async {
    await repository.add(sam);

    await expectLater(
      repository.add(
        Person(
          id: 'per_other',
          name: 'SAM',
          role: PersonRole.viewer,
          createdAt: DateTime.utc(2026),
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
