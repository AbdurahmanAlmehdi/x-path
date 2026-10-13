import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Value objects built at run time, so that equality is computed from the
/// fields and not decided by constant canonicalization.
void main() {
  test('values with the same fields are equal', () {
    List<String> list() => ['a'];
    Set<int> builds() => {1, 2};

    expect(
      GitWorktreeStatus(headSha: 'abc', changed: list(), untracked: list()),
      GitWorktreeStatus(headSha: 'abc', changed: list(), untracked: list()),
    );
    expect(
      GuardCheckResult(
        GuardCheckName.source,
        GuardStatus.failed,
        'bad',
        fix: list().single,
      ),
      GuardCheckResult(
        GuardCheckName.source,
        GuardStatus.failed,
        'bad',
        fix: list().single,
      ),
    );
    expect(
      GuardReport([
        GuardCheckResult(
          GuardCheckName.source,
          GuardStatus.passed,
          'ok',
          fix: list().single,
        ),
      ]),
      GuardReport([
        GuardCheckResult(
          GuardCheckName.source,
          GuardStatus.passed,
          'ok',
          fix: list().single,
        ),
      ]),
    );
    expect(
      AppStoreTrainStatus(liveVersion: VersionName.parse('5.4.0')),
      AppStoreTrainStatus(liveVersion: VersionName.parse('5.4.0')),
    );
    expect(
      ShorebirdRelease(
        version: AppVersion.parse('5.4.1+3283'),
        flutterVersion: '3.35.4',
      ),
      ShorebirdRelease(
        version: AppVersion.parse('5.4.1+3283'),
        flutterVersion: '3.35.4',
      ),
    );
    expect(StoreBuilds(builds()), StoreBuilds(builds()));
    expect(
      VersionFilesState(
        pubspecPath: 'pubspec.yaml',
        pubspec: AppVersion.parse('1.0.0+1'),
        plists: [PlistVersion(path: 'a.plist', literal: list().isNotEmpty)],
      ),
      VersionFilesState(
        pubspecPath: 'pubspec.yaml',
        pubspec: AppVersion.parse('1.0.0+1'),
        plists: [PlistVersion(path: 'a.plist', literal: list().isNotEmpty)],
      ),
    );
    expect(
      VersionBumpResult(
        commit: 'c',
        created: true,
        previous: AppVersion.parse('1.0.0+1'),
      ),
      VersionBumpResult(
        commit: 'c',
        created: true,
        previous: AppVersion.parse('1.0.0+1'),
      ),
    );
    expect(
      ReleaseTag(
        name: 'v1.0.0+1',
        version: VersionName.parse('1.0.0'),
        build: 1,
      ),
      ReleaseTag(
        name: 'v1.0.0+1',
        version: VersionName.parse('1.0.0'),
        build: 1,
      ),
    );
    expect(TagScope(app: list().single), TagScope(app: list().single));
  });

  test('a version file exception says which file', () {
    expect(
      const VersionFileException('pubspec.yaml', 'has no version').toString(),
      'VersionFileException: pubspec.yaml: has no version',
    );
  });
}
