import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

ShorebirdReleaseRecord record({
  String appId = 'app-1',
  String version = '1.2.3+45',
  ShorebirdPlatform platform = ShorebirdPlatform.android,
  String flutter = '3.35.4',
}) => ShorebirdReleaseRecord(
  appId: appId,
  version: AppVersion.parse(version),
  platform: platform,
  flutterVersion: flutter,
  jobId: 'job_1',
  recordedAt: DateTime.utc(2026, 10, 13),
);

void main() {
  group('ShorebirdPlatform', () {
    test('is read from its name on the command line', () {
      expect(ShorebirdPlatform.fromWire('android'), ShorebirdPlatform.android);
      expect(ShorebirdPlatform.fromWire('ios'), ShorebirdPlatform.ios);
      expect(ShorebirdPlatform.fromWire('web'), isNull);
    });
  });

  group('ShorebirdReleaseRecord', () {
    test('compares by value', () {
      expect(record(), record());
      expect(record(), isNot(record(flutter: '3.47.6')));
    });
  });

  group('InMemoryShorebirdReleaseRepository', () {
    late InMemoryShorebirdReleaseRepository repository;

    setUp(() => repository = InMemoryShorebirdReleaseRepository());

    test('finds a record by app, version and platform', () async {
      await repository.save(record());

      expect(
        await repository.find(
          'app-1',
          AppVersion.parse('1.2.3+45'),
          ShorebirdPlatform.android,
        ),
        record(),
      );
      expect(
        await repository.find(
          'app-1',
          AppVersion.parse('1.2.3+45'),
          ShorebirdPlatform.ios,
        ),
        isNull,
      );
      expect(
        await repository.find(
          'app-2',
          AppVersion.parse('1.2.3+45'),
          ShorebirdPlatform.android,
        ),
        isNull,
      );
    });

    test('replaces the record of the same release', () async {
      await repository.save(record());
      await repository.save(record(flutter: '3.47.6'));

      final found = await repository.find(
        'app-1',
        AppVersion.parse('1.2.3+45'),
        ShorebirdPlatform.android,
      );
      expect(found!.flutterVersion, '3.47.6');
    });
  });
}
