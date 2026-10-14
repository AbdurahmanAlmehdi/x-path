import 'package:test/test.dart';
import 'package:xp/src/runner/job/lease_paths.dart';

Map<String, dynamic> _worktree({
  String path = '/engine/worktrees/42/job_1',
  String mirror = '/engine/mirrors/42.git',
  Object repoId = 42,
}) => {
  'path': path,
  'mirror': {'githubRepoId': repoId, 'path': mirror},
  'sha': 'a' * 40,
};

void main() {
  test(
    'names the worktree and the cache of the runner for those of the engine',
    () {
      final paths = LeasePaths.of([
        {'worktree': _worktree()},
      ], sourceDirectory: '/runner/source');

      expect(paths.worktree!.path, '/runner/source/worktrees/42/job_1');
      expect(paths.worktree!.mirror.path, '/runner/source/mirrors/42.git');
      expect(paths.worktree!.mirror.githubRepoId, 42);
      expect(
        paths.path('/engine/worktrees/42/job_1'),
        '/runner/source/worktrees/42/job_1',
      );
      expect(
        paths.path('/engine/mirrors/42.git'),
        '/runner/source/mirrors/42.git',
      );
    },
  );

  test('keeps the rest of a path below the worktree', () {
    final paths = LeasePaths.of([
      {'worktree': _worktree()},
    ], sourceDirectory: '/runner/source');

    expect(
      paths.path('/engine/worktrees/42/job_1/apps/mobile'),
      '/runner/source/worktrees/42/job_1/apps/mobile',
    );
  });

  test('leaves other paths alone, even one that only starts alike', () {
    final paths = LeasePaths.of([
      {'worktree': _worktree()},
    ], sourceDirectory: '/runner/source');

    expect(
      paths.path('/engine/worktrees/42/job_10'),
      '/engine/worktrees/42/job_10',
    );
    expect(paths.path('ios/ExportOptions.plist'), 'ios/ExportOptions.plist');
    expect(paths.path('/usr/bin/git'), '/usr/bin/git');
  });

  test('translates every string of an input, nested ones too', () {
    final paths = LeasePaths.of([
      {'worktree': _worktree()},
    ], sourceDirectory: '/runner/source');

    final input = paths.input({
      'workingDirectory': '/engine/worktrees/42/job_1/app',
      'arguments': ['--out', '/engine/worktrees/42/job_1/out', '-v'],
      'worktree': _worktree(),
      'sideEffect': true,
      'attempts': 3,
      'nothing': null,
    });

    expect(input['workingDirectory'], '/runner/source/worktrees/42/job_1/app');
    expect(input['arguments'], [
      '--out',
      '/runner/source/worktrees/42/job_1/out',
      '-v',
    ]);
    final worktree = input['worktree']! as Map<String, dynamic>;
    expect(worktree['path'], '/runner/source/worktrees/42/job_1');
    expect(
      (worktree['mirror'] as Map)['path'],
      '/runner/source/mirrors/42.git',
    );
    expect(worktree['sha'], 'a' * 40);
    expect(input['sideEffect'], isTrue);
    expect(input['attempts'], 3);
    expect(input['nothing'], isNull);
  });

  test('translates nothing for a job without a worktree', () {
    final paths = LeasePaths.of([
      {'executable': 'echo'},
      {'worktree': 'not a map'},
      {
        'worktree': {'path': '/engine/w'},
      },
      {
        'worktree': {
          'path': '/engine/w',
          'mirror': {'path': '/engine/m', 'githubRepoId': 'x'},
        },
      },
      {
        'worktree': {
          'path': '/engine/w',
          'mirror': {'githubRepoId': 1},
        },
      },
    ], sourceDirectory: '/runner/source');

    expect(paths.worktree, isNull);
    expect(paths.path('/engine/w'), '/engine/w');
  });

  test('takes the worktree from the first step that has one', () {
    final paths = LeasePaths.of([
      {'executable': 'echo'},
      {
        'worktree': _worktree(
          path: '/e/w/7/job_9',
          mirror: '/e/m/7.git',
          repoId: 7,
        ),
      },
    ], sourceDirectory: '/r/source');

    expect(paths.worktree!.path, '/r/source/worktrees/7/job_9');
  });
}
