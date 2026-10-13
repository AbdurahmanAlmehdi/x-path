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

  test('GitTagInfo compares by value', () {
    expect(
      const GitTagInfo(name: 'v1', commit: 'abc'),
      const GitTagInfo(name: 'v1', commit: 'abc'),
    );
    expect(
      const GitTagInfo(name: 'v1', commit: 'abc'),
      isNot(const GitTagInfo(name: 'v1', commit: 'def')),
    );
  });

  test('GitWorktreeStatus is clean only without changes and extra files', () {
    expect(const GitWorktreeStatus(headSha: 'abc').isClean, isTrue);
    expect(
      const GitWorktreeStatus(headSha: 'abc', changed: ['a']).isClean,
      isFalse,
    );
    expect(
      const GitWorktreeStatus(headSha: 'abc', untracked: ['a']).isClean,
      isFalse,
    );
    expect(
      const GitWorktreeStatus(headSha: 'abc', changed: ['a']),
      const GitWorktreeStatus(headSha: 'abc', changed: ['a']),
    );
  });

  test('GitCommitResult compares by value', () {
    expect(
      const GitCommitResult(sha: 'a', tree: 't', created: true),
      const GitCommitResult(sha: 'a', tree: 't', created: true),
    );
    expect(
      const GitCommitResult(sha: 'a', tree: 't', created: true),
      isNot(const GitCommitResult(sha: 'a', tree: 't', created: false)),
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
