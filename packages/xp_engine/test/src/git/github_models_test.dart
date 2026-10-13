import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('GitHubRepo', () {
    const repo = GitHubRepo(
      id: 1,
      fullName: 'acme/app',
      defaultBranch: 'main',
      cloneUrl: 'https://github.com/acme/app.git',
    );

    test('splits the full name', () {
      expect(repo.owner, 'acme');
      expect(repo.name, 'app');
    });

    test('compares by value, renamedFrom included', () {
      expect(
        repo,
        const GitHubRepo(
          id: 1,
          fullName: 'acme/app',
          defaultBranch: 'main',
          cloneUrl: 'https://github.com/acme/app.git',
        ),
      );
      expect(
        repo,
        isNot(
          const GitHubRepo(
            id: 1,
            fullName: 'acme/app',
            defaultBranch: 'main',
            cloneUrl: 'https://github.com/acme/app.git',
            renamedFrom: 'acme/old',
          ),
        ),
      );
    });
  });

  test('GitHubPullRequest compares by value', () {
    const pr = GitHubPullRequest(
      number: 3,
      title: 'Release',
      state: GitHubPullRequestState.open,
      headRef: 'release/1.0',
      headSha: 'abc',
      baseRef: 'main',
      htmlUrl: 'https://github.com/acme/app/pull/3',
    );

    expect(
      pr,
      const GitHubPullRequest(
        number: 3,
        title: 'Release',
        state: GitHubPullRequestState.open,
        headRef: 'release/1.0',
        headSha: 'abc',
        baseRef: 'main',
        htmlUrl: 'https://github.com/acme/app/pull/3',
      ),
    );
    expect(
      pr,
      isNot(
        const GitHubPullRequest(
          number: 3,
          title: 'Release',
          state: GitHubPullRequestState.merged,
          headRef: 'release/1.0',
          headSha: 'abc',
          baseRef: 'main',
          htmlUrl: 'https://github.com/acme/app/pull/3',
          mergeCommitSha: 'def',
        ),
      ),
    );
    expect(pr.mergeCommitSha, isNull);
  });

  test('GitHubMergeMethod maps to the API values', () {
    expect(GitHubMergeMethod.merge.apiValue, 'merge');
    expect(GitHubMergeMethod.squash.apiValue, 'squash');
    expect(GitHubMergeMethod.rebase.apiValue, 'rebase');
  });

  test('GitHubMergeResult compares by value', () {
    final result = GitHubMergeResult(sha: ['a'].first, message: 'ok');

    expect(result, GitHubMergeResult(sha: ['a'].first, message: 'ok'));
    expect(result, isNot(const GitHubMergeResult(sha: 'b', message: 'ok')));
  });

  test('GitHubException subclasses carry their status code', () {
    const all = <GitHubException>[
      GitHubException(500, 'x'),
      GitHubAuthException('x'),
      GitHubForbiddenException('x'),
      GitHubNotFoundException('x'),
      GitHubNotMergeableException('x'),
      GitHubConflictException('x'),
      GitHubValidationException('x'),
    ];

    expect(all.map((e) => e.statusCode), [500, 401, 403, 404, 405, 409, 422]);
    expect(all.map((e) => e.message).toSet(), {'x'});
    expect(all.map((e) => e.toString()), [
      'GitHubException(500): x',
      'GitHubAuthException: x',
      'GitHubForbiddenException: x',
      'GitHubNotFoundException: x',
      'GitHubNotMergeableException: x',
      'GitHubConflictException: x',
      'GitHubValidationException: x',
    ]);
  });

  test('GitHubForbiddenException says whether it is the rate limit', () {
    expect(const GitHubForbiddenException('x').rateLimited, isFalse);
    expect(
      const GitHubForbiddenException('x', rateLimited: true).rateLimited,
      isTrue,
    );
  });

  test('the GitHub token lives under github.token', () {
    expect(githubTokenSecretKey, 'github.token');
  });
}
