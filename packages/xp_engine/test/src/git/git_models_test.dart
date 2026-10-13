import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const mirror = GitMirror(githubRepoId: 7, path: '/data/mirrors/7.git');

  test('GitMirror compares by value', () {
    expect(
      mirror,
      const GitMirror(githubRepoId: 7, path: '/data/mirrors/7.git'),
    );
    expect(
      mirror,
      isNot(const GitMirror(githubRepoId: 8, path: '/data/mirrors/7.git')),
    );
  });

  test('GitWorktree compares by value', () {
    const worktree = GitWorktree(mirror: mirror, path: '/w/job', sha: 'abc');

    expect(
      worktree,
      const GitWorktree(mirror: mirror, path: '/w/job', sha: 'abc'),
    );
    expect(
      worktree,
      isNot(const GitWorktree(mirror: mirror, path: '/w/job', sha: 'def')),
    );
  });

  test('GitRefspecs never force and name the same ref on both sides', () {
    expect(
      GitRefspecs.branch('release/1.2'),
      'refs/heads/release/1.2:refs/heads/release/1.2',
    );
    expect(
      GitRefspecs.tag('v1.2.3+45'),
      'refs/tags/v1.2.3+45:refs/tags/v1.2.3+45',
    );
  });
}
