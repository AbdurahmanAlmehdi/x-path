import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';

void main() {
  const check = PatchTargetCheck();

  test('names itself patchTarget', () {
    expect(check.name, GuardCheckName.patchTarget);
  });

  group('without Shorebird data', () {
    test('passes for a release that has a tag', () async {
      final git = guardRequest(releaseVersion: '5.4.1+3283').git
        ..tags.add(tag('v5.4.1+3283'));

      final result = await check.run(
        guardRequest(git: git, releaseVersion: '5.4.1+3283').request,
      );

      expect(result.status, GuardStatus.passed);
      expect(result.message, 'Patch target 5.4.1+3283.');
    });

    test('warns when the release has no tag', () async {
      final result = await check.run(
        guardRequest(releaseVersion: '5.4.1+3283').request,
      );

      expect(result.status, GuardStatus.warned);
      expect(
        result.message,
        startsWith(
          'No tag v5.4.1+3283; check that 5.4.1+3283 is the release you mean.',
        ),
      );
    });

    test('looks for the tag the release model names', () async {
      final git = guardRequest().git..tags.add(tag('mobile/prod/v5.4.1+3283'));

      final result = await check.run(
        guardRequest(
          git: git,
          releaseVersion: '5.4.1+3283',
          model: const ReleaseModel(
            tagPattern: '{app}/{flavor}/v{version}+{build}',
          ),
          scope: const TagScope(app: 'mobile', flavor: 'prod'),
        ).request,
      );

      expect(result.status, GuardStatus.passed);
    });
  });

  // Incident: ship.sh patch --release-version latest patched whichever
  // release was cut last while an older one was the live one (R:149-155).
  group('fails', () {
    test('for "latest" (real incident)', () async {
      final result = await check.run(
        guardRequest(releaseVersion: 'latest').request,
      );

      expect(result.status, GuardStatus.failed);
      expect(result.message, contains("'latest' is whichever release"));
      expect(result.fix, contains('5.4.1+3283'));
    });

    test('when no release is named', () async {
      final result = await check.run(guardRequest().request);

      expect(result.status, GuardStatus.failed);
      expect(result.message, 'A patch needs the release it patches.');
    });

    test('for a release without a build number', () async {
      final result = await check.run(
        guardRequest(releaseVersion: '5.4.1').request,
      );

      expect(result.status, GuardStatus.failed);
      expect(result.message, contains('names no single release'));
    });

    test('for a version that is not a version', () async {
      final result = await check.run(
        guardRequest(releaseVersion: 'five').request,
      );

      expect(result.status, GuardStatus.failed);
      expect(result.message, contains('is not a version'));
    });
  });

  group('with Shorebird data', () {
    final release = ShorebirdRelease(
      version: AppVersion.parse('5.4.1+3283'),
      flutterVersion: '3.35.4',
    );
    late FakeShorebirdReleases shorebird;

    setUp(() => shorebird = FakeShorebirdReleases([release]));

    Future<GuardCheckResult> run({String version = '5.4.1+3283'}) {
      final git = guardRequest().git..tags.add(tag('v5.4.1+3283'));
      return PatchTargetCheck(shorebird: shorebird).run(
        guardRequest(
          git: git,
          releaseVersion: version,
          shorebirdAppId: 'sb-1234',
        ).request,
      );
    }

    test('passes and says which Flutter version the patch uses', () async {
      final result = await run();

      expect(result.status, GuardStatus.passed);
      expect(result.message, contains('The patch will use Flutter 3.35.4'));
      expect(shorebird.lookups, ['sb-1234']);
    });

    test('fails for a release Shorebird does not have', () async {
      final result = await run(version: '5.4.1+3290');

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'Shorebird has no release 5.4.1+3290 for sb-1234. It has: '
        '5.4.1+3283.',
      );
    });

    test('fails when Shorebird has no release at all', () async {
      shorebird.answer = const [];

      expect((await run()).message, endsWith('It has: none.'));
    });

    test('warns when the releases cannot be listed', () async {
      shorebird.answer = null;

      final result = await run();

      expect(result.status, GuardStatus.warned);
      expect(result.message, contains('Could not list the Shorebird releases'));
    });

    test('is not asked for a flavor without a Shorebird app', () async {
      final result = await PatchTargetCheck(shorebird: shorebird)
          .run(guardRequest(releaseVersion: '5.4.1+3283').request);

      expect(result.status, GuardStatus.warned);
      expect(shorebird.lookups, isEmpty);
    });
  });
}
