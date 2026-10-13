import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';

void main() {
  late FakeAppStoreTrains trains;
  late AppStoreTrainCheck check;

  VersionName v(String text) => VersionName.parse(text);

  setUp(() {
    trains = FakeAppStoreTrains(AppStoreTrainStatus(liveVersion: v('5.4.0')));
    check = AppStoreTrainCheck(trains);
  });

  test('names itself appStoreTrain', () {
    expect(check.name, GuardCheckName.appStoreTrain);
  });

  // Incident: the customer app was built and uploaded as 5.4.0+3290 while
  // 5.4.0 was live. App Store Connect rejected the upload after the full
  // build with "ITMS-90186: Invalid Pre-Release Train. The train version
  // '5.4.0' is closed for new build submissions". The iTunes lookup says it
  // in a second (R:168-188).
  test('fails when 5.4.0 is live already: 90186 (real incident)', () async {
    final harness = guardRequest(files: customerApp('5.4.0+3290'));

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      'The App Store already has 5.4.0 live. Version 5.4.0 is not higher, so '
      'App Store Connect would reject the upload (closed train, error 90186).',
    );
    expect(result.fix, 'Bump to a version higher than 5.4.0.');
    expect(trains.lookups, ['com.mataa.app us']);
  });

  test('fails when the version is below the live one', () async {
    final harness = guardRequest(files: customerApp('5.3.9+3200'));

    expect((await check.run(harness.request)).status, GuardStatus.failed);
  });

  test('fails when App Store Connect approved the version', () async {
    trains.answer = AppStoreTrainStatus(
      liveVersion: v('5.4.0'),
      closedVersions: {v('5.4.1')},
    );
    final harness = guardRequest(files: customerApp('5.4.1+3291'));

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.failed);
    expect(result.message, contains('already approved version 5.4.1'));
    expect(result.message, contains('90186'));
  });

  test('passes for a version higher than the live one', () async {
    final harness = guardRequest(files: customerApp('5.4.1+3291'));

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.passed);
    expect(result.message, 'The App Store has 5.4.0 live; 5.4.1 is higher.');
  });

  test('passes for an app that is not on sale yet', () async {
    trains.answer = const AppStoreTrainStatus();
    final harness = guardRequest(files: customerApp('1.0.0+1'));

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.passed);
    expect(result.message, contains('no live version'));
  });

  test('warns when the App Store cannot be read', () async {
    trains.answer = null;

    final result = await check.run(guardRequest().request);

    expect(result.status, GuardStatus.warned);
    expect(result.message, contains('Could not read the App Store state'));
  });

  test('is skipped for a flavor without an iOS bundle id', () async {
    final result = await check.run(guardRequest(iosBundleId: null).request);

    expect(result.status, GuardStatus.skipped);
    expect(trains.lookups, isEmpty);
  });

  test('fails, instead of throwing, when the pubspec has no version', () async {
    final harness = guardRequest(
      files: {'pubspec.yaml': 'name: x\n'},
      versionFiles: ['pubspec.yaml'],
    );

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.failed);
    expect(result.message, startsWith('pubspec.yaml:'));
  });
}
