import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';

void main() {
  late FakePlayRequirements play;
  late PlayTargetSdkCheck check;

  setUp(() {
    play = FakePlayRequirements(35);
    check = PlayTargetSdkCheck(play);
  });

  Future<GuardCheckResult> run(
    Map<String, String> files, {
    String appPath = '.',
  }) => check.run(
    guardRequest(
      files: {'pubspec.yaml': 'version: 1.0.0+1\n', ...files},
      versionFiles: ['pubspec.yaml'],
      appPath: appPath,
    ).request,
  );

  test('names itself playTargetSdk', () {
    expect(check.name, GuardCheckName.playTargetSdk);
  });

  // Incident: Google Play began to refuse updates that target below API 35
  // (D-22); the app still said targetSdk = 34 in its Gradle script.
  test(
    'fails when the app targets a lower API level (real incident)',
    () async {
      final result = await run({
        'android/app/build.gradle.kts': gradle(targetSdk: '34'),
      });

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'The app targets API 34; Google Play asks for 35 or higher.',
      );
      expect(result.fix, contains('targetSdk to 35'));
    },
  );

  test('passes at and above the required level', () async {
    for (final level in ['35', '36']) {
      final result = await run({
        'android/app/build.gradle.kts': gradle(targetSdk: level),
      });

      expect(result.status, GuardStatus.passed, reason: level);
    }
  });

  test('reads the Groovy spellings', () async {
    for (final line in [
      'targetSdkVersion 34',
      'targetSdkVersion(34)',
      'targetSdk 34',
    ]) {
      final result = await run({
        'android/app/build.gradle': 'android { defaultConfig { $line } }',
      });

      expect(result.status, GuardStatus.failed, reason: line);
    }
  });

  test('warns when the level comes from Flutter', () async {
    final result = await run({
      'android/app/build.gradle.kts': gradle(
        targetSdk: 'flutter.targetSdkVersion',
      ),
    });

    expect(result.status, GuardStatus.warned);
    expect(result.message, contains("from Flutter's default"));
  });

  test('ignores a level in a comment', () async {
    final result = await run({
      'android/app/build.gradle.kts': gradle(targetSdk: '36'),
    });

    expect(result.status, GuardStatus.passed);
  });

  test('looks at the other Gradle scripts after build.gradle', () async {
    final result = await run({
      'android/app/build.gradle.kts': 'android { }',
      'android/app/flavorizr.gradle.kts': 'targetSdk = 30',
      'android/app/notes.txt': 'targetSdk = 99',
    });

    expect(result.status, GuardStatus.failed);
  });

  test('works for an app below the root', () async {
    final result = await run({
      'apps/m/android/app/build.gradle.kts': gradle(targetSdk: '34'),
    }, appPath: 'apps/m');

    expect(result.status, GuardStatus.failed);
  });

  test('warns when Google Play cannot be asked', () async {
    play.answer = null;

    final result = await run({
      'android/app/build.gradle.kts': gradle(targetSdk: '34'),
    });

    expect(result.status, GuardStatus.warned);
  });

  test('is skipped for an app without an Android project', () async {
    final result = await run({});

    expect(result.status, GuardStatus.skipped);
  });
}
