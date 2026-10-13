import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';

void main() {
  late FakeStoreBuildNumbers stores;
  late BuildNumberReuseCheck check;

  setUp(() {
    stores = FakeStoreBuildNumbers(const StoreBuilds({3280, 3282}));
    check = BuildNumberReuseCheck(stores);
  });

  GuardRequest request({
    String version = '5.4.1+3283',
    List<GitTagInfo> tags = const [],
  }) => guardRequest(
    files: customerApp(version),
    git: guardRequest().git..tags.addAll(tags),
  ).request;

  test('names itself buildNumberReuse', () {
    expect(check.name, GuardCheckName.buildNumberReuse);
  });

  test('passes for a build neither store nor tags have seen', () async {
    final result = await check.run(request(tags: [tag('v5.4.0+3282')]));

    expect(result.status, GuardStatus.passed);
    expect(stores.lookups, ['com.mataa.app com.mataa.app']);
  });

  // Incident: build 3282 had been uploaded to App Store Connect by hand
  // before the ledger existed, so no tag knew it; the upload of 5.4.1+3282
  // was rejected as a duplicate after the whole build.
  test('fails for a build the store already has (real incident)', () async {
    final result = await check.run(request(version: '5.4.1+3282'));

    expect(result.status, GuardStatus.failed);
    expect(result.message, 'The store already has a build 3282.');
    expect(result.fix, contains('Allocate a new build number'));
  });

  test('fails for a build another tag recorded', () async {
    final result = await check.run(
      request(tags: [tag('v5.3.0+3283', otherSha)]),
    );

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      'Build 3283 is already used by the tag v5.3.0+3283.',
    );
    expect(stores.lookups, isEmpty);
  });

  test('passes for the tag of this very release on this commit', () async {
    stores.builds = const StoreBuilds({3283});

    final result = await check.run(
      request(tags: [tag('v5.4.1+3283', dispatchedSha)]),
    );

    expect(result.status, GuardStatus.passed);
    expect(result.message, contains('same release'));
  });

  test(
    'refuses the same build on another commit of the same version',
    () async {
      final result = await check.run(
        request(tags: [tag('v5.4.1+3283', otherSha)]),
      );

      expect(result.status, GuardStatus.failed);
    },
  );

  test(
    'warns, after checking the tags, when the stores cannot be asked',
    () async {
      stores.builds = null;

      final result = await check.run(request());

      expect(result.status, GuardStatus.warned);
      expect(result.message, contains('only the tags were checked'));
    },
  );

  test('fails for a pubspec without a build number', () async {
    final result = await check.run(
      guardRequest(
        files: {'pubspec.yaml': 'version: 5.4.1\n'},
        versionFiles: ['pubspec.yaml'],
      ).request,
    );

    expect(result.status, GuardStatus.failed);
    expect(result.message, contains('has no build number'));
  });
}
