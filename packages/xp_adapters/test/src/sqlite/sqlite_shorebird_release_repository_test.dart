import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

ShorebirdReleaseRecord _record({
  String flutter = '3.35.4',
  ShorebirdPlatform platform = ShorebirdPlatform.android,
  String job = 'job_1',
}) => ShorebirdReleaseRecord(
  appId: 'sb-1',
  version: AppVersion.parse('1.2.3+45'),
  platform: platform,
  flutterVersion: flutter,
  jobId: job,
  recordedAt: DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456),
);

void main() {
  late SqliteDatabase database;
  late SqliteShorebirdReleaseRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteShorebirdReleaseRepository(database);
  });

  Future<ShorebirdReleaseRecord?> find({
    String appId = 'sb-1',
    ShorebirdPlatform platform = ShorebirdPlatform.android,
  }) => repository.find(appId, AppVersion.parse('1.2.3+45'), platform);

  test('keeps a record and reads it back', () async {
    await repository.save(_record());

    expect(await find(), _record());
  });

  test('has no record that was not saved', () async {
    await repository.save(_record());

    expect(await find(appId: 'sb-2'), isNull);
    expect(await find(platform: ShorebirdPlatform.ios), isNull);
    expect(
      await repository.find(
        'sb-1',
        AppVersion.parse('1.2.3+46'),
        ShorebirdPlatform.android,
      ),
      isNull,
    );
  });

  test('keeps a record per platform', () async {
    await repository.save(_record());
    await repository.save(
      _record(platform: ShorebirdPlatform.ios, flutter: '3.32.0'),
    );

    expect((await find())!.flutterVersion, '3.35.4');
    expect(
      (await find(platform: ShorebirdPlatform.ios))!.flutterVersion,
      '3.32.0',
    );
  });

  test('replaces the record of the same release', () async {
    await repository.save(_record());
    await repository.save(_record(flutter: '3.47.6', job: 'job_2'));

    final found = await find();
    expect(found!.flutterVersion, '3.47.6');
    expect(found.jobId, 'job_2');
    expect(
      database.connection.select('SELECT * FROM shorebird_release'),
      hasLength(1),
    );
  });
}
