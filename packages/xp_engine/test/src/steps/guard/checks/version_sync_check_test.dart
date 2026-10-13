import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';
import '../../../../helpers/version_fixtures.dart';

void main() {
  const check = VersionSyncCheck();

  test('names itself versionSync', () {
    expect(check.name, GuardCheckName.versionSync);
  });

  test('passes when the pubspec and the plists say the same', () async {
    final result = await check.run(guardRequest().request);

    expect(result.status, GuardStatus.passed);
    expect(result.message, 'pubspec.yaml and 2 plist(s) say 5.4.1+3283.');
  });

  test('passes when no plist carries a literal version', () async {
    final harness = guardRequest(
      files: {
        'pubspec.yaml': pubspec('5.4.1+3283'),
        'ios/Runner/Info.plist': flutterPlist,
      },
      versionFiles: ['pubspec.yaml', 'ios/Runner/Info.plist'],
    );

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.passed);
    expect(result.message, contains('no plist carries a literal version'));
  });

  test('passes for a pubspec alone', () async {
    final harness = guardRequest(
      files: {'pubspec.yaml': pubspec('5.4.1+3283')},
      versionFiles: [],
    );

    expect((await check.run(harness.request)).status, GuardStatus.passed);
  });

  // Incident: the customer app's plists carry literal versions, so
  // `--build-number` never reaches iOS; a pubspec bumped by hand left the
  // dev plist at the old build (R:92-103).
  test('fails when a plist lags behind the pubspec (real incident)', () async {
    final harness = guardRequest(
      files: {
        ...customerApp('5.4.1+3283'),
        'ios/Runner/Info-Dev.plist': plist('5.4.0', '3282'),
      },
    );

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      "ios/Runner/Info-Dev.plist says '5.4.0 3282' but pubspec.yaml says "
      "'5.4.1 3283'.",
    );
    expect(result.fix, contains('version.bump'));
  });

  test('fails when only the build number differs', () async {
    final harness = guardRequest(
      files: {
        ...customerApp('5.4.1+3283'),
        'ios/Runner/Info.plist': plist('5.4.1', '3280'),
      },
    );

    expect((await check.run(harness.request)).status, GuardStatus.failed);
  });

  test('fails for a plist with two build numbers', () async {
    final harness = guardRequest(
      files: {
        ...customerApp('5.4.1+3283'),
        'ios/Runner/Info.plist':
            '<key>CFBundleShortVersionString</key><string>5.4.1</string>'
            '<key>CFBundleVersion</key><string>1</string>'
            '<key>CFBundleVersion</key><string>2</string>',
      },
    );

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.failed);
    expect(result.message, contains('2 matches for CFBundleVersion'));
  });
}
