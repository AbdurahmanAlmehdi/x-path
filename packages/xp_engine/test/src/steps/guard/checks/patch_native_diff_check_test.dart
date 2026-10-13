import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';

void main() {
  const check = PatchNativeDiffCheck();

  test('names itself patchNativeDiff', () {
    expect(check.name, GuardCheckName.patchNativeDiff);
  });

  GuardRequest request({
    List<String> changed = const [],
    List<GitTagInfo>? tags,
    String? releaseVersion = '5.4.1+3283',
    String appPath = '.',
  }) {
    final git = guardRequest().git
      ..changed = changed
      ..tags.addAll(tags ?? [tag('v5.4.1+3283')]);
    return guardRequest(
      git: git,
      releaseVersion: releaseVersion,
      appPath: appPath,
    ).request;
  }

  test('passes when only Dart and assets changed', () async {
    final harness = guardRequest(releaseVersion: '5.4.1+3283');
    harness.git
      ..tags.add(tag('v5.4.1+3283'))
      ..changed = ['lib/main.dart', 'assets/logo.png', 'pubspec.yaml'];

    final result = await check.run(harness.request);

    expect(result.status, GuardStatus.passed);
    expect(result.message, contains('patch-eligible'));
    expect(
      harness.git.calls,
      contains('changedFiles v5.4.1+3283 $dispatchedSha'),
    );
  });

  // Incident: a Kotlin plugin change and an Info.plist edit were patched over
  // the air and failed at runtime, not at build (O:643-657).
  test('fails when native files changed (real incident)', () async {
    final result = await check.run(
      request(
        changed: [
          'lib/main.dart',
          'android/app/src/main/kotlin/com/mataa/MainActivity.kt',
          'ios/Runner/Info.plist',
        ],
      ),
    );

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      'Native files changed since v5.4.1+3283:\n'
      '  android/app/src/main/kotlin/com/mataa/MainActivity.kt\n'
      '  ios/Runner/Info.plist',
    );
    expect(result.fix, 'This needs a full store release, not a patch.');
  });

  test('looks only inside the app folder of a monorepo', () async {
    final result = await check.run(
      request(
        appPath: 'apps/captain',
        changed: ['android/build.gradle', 'apps/captain/lib/a.dart'],
      ),
    );
    final native = await check.run(
      request(appPath: 'apps/captain', changed: ['apps/captain/ios/Podfile']),
    );

    expect(result.status, GuardStatus.passed);
    expect(native.status, GuardStatus.failed);
  });

  test('counts every platform folder as native', () async {
    for (final folder in PatchNativeDiffCheck.nativeFolders) {
      final result = await check.run(request(changed: ['$folder/x']));

      expect(result.status, GuardStatus.failed, reason: folder);
    }
    expect(
      (await check.run(request(changed: ['android_notes/x']))).status,
      GuardStatus.passed,
    );
  });

  test('refuses to patch blind without the tag of the release', () async {
    final result = await check.run(request(tags: []));

    expect(result.status, GuardStatus.failed);
    expect(result.message, contains('No tag v5.4.1+3283'));
    expect(result.message, contains('Refusing to patch blind'));
  });

  test('fails when the release is not exact', () async {
    for (final version in [null, 'latest', '5.4.1']) {
      final result = await check.run(request(releaseVersion: version));

      expect(result.status, GuardStatus.failed, reason: '$version');
    }
  });
}
