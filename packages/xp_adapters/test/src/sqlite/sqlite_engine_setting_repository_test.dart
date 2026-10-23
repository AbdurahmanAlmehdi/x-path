import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

void main() {
  late SqliteDatabase database;
  late SqliteEngineSettingRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteEngineSettingRepository(database);
  });

  test('has nothing until a value is written', () async {
    expect(await repository.read('runner_url'), isNull);
  });

  test('keeps a value, replaces it and clears it', () async {
    await repository.write('runner_url', 'https://a.ts.net');
    await repository.write('runner_url', 'https://b.ts.net');
    await repository.write('other', 'x');

    expect(await repository.read('runner_url'), 'https://b.ts.net');
    expect(
      database.connection.select('SELECT count(*) AS n FROM engine_setting'),
      [
        {'n': 2},
      ],
    );

    await repository.write('runner_url', null);

    expect(await repository.read('runner_url'), isNull);
    expect(await repository.read('other'), 'x');
  });
}
