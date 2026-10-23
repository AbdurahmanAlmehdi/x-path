import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const worktree = ReleaseWorktree(
    path: '/work/job_1',
    mirror: GitMirror(key: '7', path: '/m/7.git'),
    sha: 'abc',
    appPath: 'apps/m',
    versionFiles: ['apps/m/pubspec.yaml', 'apps/m/ios/Runner/Info.plist'],
    releaseModel: ReleaseModel(branchPattern: 'rel/{version}'),
    scope: TagScope(app: 'm', flavor: 'prod'),
  );

  test('round-trips through JSON', () {
    expect(ReleaseWorktree.fromJson(worktree.toJson()), worktree);
  });

  test('stores the mirror by its key', () {
    expect(worktree.toJson()['mirror'], {'key': '7', 'path': '/m/7.git'});
  });

  test('reads the GitHub id of a job stored before ADR 0015 as its key', () {
    final read = ReleaseWorktree.fromJson(const {
      'path': '/w',
      'mirror': {'githubRepoId': 12, 'path': '/m/12.git'},
      'sha': 'abc',
    });

    expect(read.mirror, const GitMirror(key: '12', path: '/m/12.git'));
    expect(ReleaseWorktree.mirrorKeyOf(const {'path': '/m'}), isNull);
  });

  test('needs only the path, mirror and commit', () {
    final read = ReleaseWorktree.fromJson(const {
      'path': '/w',
      'mirror': {'key': 'h0123456789abcdef', 'path': '/m.git'},
      'sha': 'abc',
    });

    expect(read.appPath, '.');
    expect(read.versionFiles, isEmpty);
    expect(read.releaseModel, const ReleaseModel());
    expect(read.scope, const TagScope());
    expect(read.toJson()['scope'], isEmpty);
  });

  test('describes the git worktree and the paths inside the app', () {
    expect(worktree.gitWorktree.path, '/work/job_1');
    expect(worktree.gitWorktree.sha, 'abc');
    expect(worktree.gitWorktree.mirror.key, '7');
    expect(worktree.inApp('lib/main.dart'), 'apps/m/lib/main.dart');
    expect(worktree.versionFilePaths, worktree.versionFiles);
    expect(
      const ReleaseWorktree(
        path: '/w',
        mirror: GitMirror(key: '1', path: '/m'),
        sha: 'a',
        appPath: 'apps/m',
      ).versionFilePaths,
      ['apps/m/pubspec.yaml'],
    );
    expect(
      const ReleaseWorktree(
        path: '/w',
        mirror: GitMirror(key: '1', path: '/m'),
        sha: 'a',
      ).versionFilePaths,
      ['pubspec.yaml'],
    );
  });

  test('rejects stored input that is not valid', () {
    final cases = <String, Map<String, dynamic>>{
      '"path"': {...worktree.toJson(), 'path': ''},
      '"mirror"': {...worktree.toJson(), 'mirror': 'm'},
      '"mirror.key"': {
        ...worktree.toJson(),
        'mirror': {'githubRepoId': '7', 'path': '/m'},
      },
      '"appPath"': {...worktree.toJson(), 'appPath': 3},
      '"versionFiles"': {...worktree.toJson(), 'versionFiles': 'a'},
      'Unknown release model key': {
        ...worktree.toJson(),
        'releaseModel': {'nope': 'x'},
      },
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(
        () => ReleaseWorktree.fromJson(value),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(key),
          ),
        ),
        reason: key,
      );
    }
    expect(
      () => ReleaseWorktree.fromJson({...worktree.toJson()}..remove('mirror')),
      throwsFormatException,
    );
  });
}
