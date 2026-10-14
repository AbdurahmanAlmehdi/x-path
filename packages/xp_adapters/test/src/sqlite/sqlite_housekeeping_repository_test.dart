import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  late SqliteDatabase database;
  late SqliteHousekeepingRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteHousekeepingRepository(database);
  });

  test(
    'has the default retention and no pruning until told otherwise',
    () async {
      expect(await repository.retention(), const RetentionSettings());
      expect(await repository.lastLogPrune(), isNull);
    },
  );

  test('keeps the retention, replacing it', () async {
    await repository.saveRetention(
      const RetentionSettings(keepPerFlavor: 2, logDays: 30),
    );
    await repository.saveRetention(const RetentionSettings(keepPerFlavor: 9));

    expect(
      await repository.retention(),
      const RetentionSettings(keepPerFlavor: 9),
    );
    expect(
      database.connection
          .select(
            "SELECT value FROM housekeeping_setting WHERE key = 'retention'",
          )
          .single['value'],
      '{"keepPerFlavor":9,"logDays":90}',
    );
  });

  test('keeps the time of the last pruning to the microsecond', () async {
    final at = DateTime.utc(2026, 10, 14, 9, 30, 15, 123, 456);

    await repository.saveLogPrune(at);

    expect(await repository.lastLogPrune(), at);
  });
}
