import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/pull_request_github.dart';
import '../../helpers/step_context.dart';

const _repo = GitHubRepo(
  id: 42,
  fullName: 'octo/demo',
  defaultBranch: 'main',
  cloneUrl: 'https://github.com/octo/demo.git',
);

void main() {
  late PullRequestGitHub github;
  final context = NoProcessContext();

  setUp(() => github = PullRequestGitHub(_repo));

  test('the results are values', () {
    GitHubCreatePrResult created(int number) => GitHubCreatePrResult(
      number: number,
      url: 'u',
      headSha: 'h',
      reused: false,
    );
    GitHubMergePrResult merged(int number) =>
        GitHubMergePrResult(number: number, sha: 's', alreadyMerged: false);

    expect(created(1), created(1));
    expect(created(1), isNot(created(2)));
    expect(merged(1), merged(1));
    expect(merged(1), isNot(merged(2)));
  });

  group('github.createPr', () {
    const input = GitHubCreatePrInput(
      githubRepoId: 42,
      head: 'release/1.2.0',
      base: 'main',
      title: 'Release 1.2.0',
      body: 'Merge it when live.',
    );

    late GitHubCreatePrStep step;

    setUp(() => step = GitHubCreatePrStep(github));

    test('has a side effect and a stored form', () {
      expect(step.kind, 'github.createPr');
      expect(step.sideEffectOf(input), isTrue);
      final stored = step.encodeInput(input);
      expect(stored, {
        'githubRepoId': 42,
        'head': 'release/1.2.0',
        'base': 'main',
        'title': 'Release 1.2.0',
        'body': 'Merge it when live.',
      });
      expect(step.decodeInput(stored), input);
      expect(
        step.decodeInput({
          'githubRepoId': 42,
          'head': 'h',
          'base': 'b',
          'title': 't',
        }).body,
        isNull,
      );
    });

    test('refuses an input that is not valid', () {
      expect(
        () => step.decodeInput({'head': 'h', 'base': 'b', 'title': 't'}),
        throwsFormatException,
      );
      expect(
        () => step.decodeInput({'githubRepoId': 42, 'head': 'h'}),
        throwsFormatException,
      );
    });

    test('opens the pull request of the release branch', () async {
      final outcome = await step.run(input, context);

      final result = (outcome as StepSucceeded<GitHubCreatePrResult>).result;
      expect(result.number, 1);
      expect(result.url, 'https://github.com/octo/demo/pull/1');
      expect(result.headSha, 'b' * 40);
      expect(result.reused, isFalse);
      expect(step.encodeResult(result), {
        'number': 1,
        'url': 'https://github.com/octo/demo/pull/1',
        'headSha': 'b' * 40,
        'reused': false,
      });
      expect(github.calls, [
        'getRepoById 42',
        'findPullRequest release/1.2.0 main',
        'getRepoById 42',
        'createPullRequest release/1.2.0 main Release 1.2.0',
      ]);
    });

    test('reuses the pull request that is open', () async {
      await step.run(input, context);

      final outcome = await step.run(input, context);

      final result = (outcome as StepSucceeded<GitHubCreatePrResult>).result;
      expect(result.number, 1);
      expect(result.reused, isTrue);
      expect(github.pulls, hasLength(1));
    });

    test('is done when the pull request is open', () async {
      expect(await step.alreadyDone(input, context), isNull);
      await step.run(input, context);

      expect((await step.alreadyDone(input, context))!.number, 1);
    });

    test('fails with what GitHub said', () async {
      github.failure = const GitHubValidationException('No commits between');

      final outcome = await step.run(input, context);

      expect(
        (outcome as StepFailed).message,
        'GitHub refused the pull request: No commits between',
      );
    });
  });

  group('github.mergePr', () {
    const input = GitHubMergePrInput(releaseId: 'rel_1', githubRepoId: 42);

    late InMemoryReleaseRepository releases;
    late GitHubMergePrStep step;

    ReleaseRecord release({
      ReleaseState state = ReleaseState.live,
      int? prNumber = 1,
    }) => ReleaseRecord(
      id: 'rel_1',
      projectId: 'prj_1',
      appPath: '.',
      flavor: 'prod',
      version: '1.2.0',
      build: 5,
      state: state,
      stores: const {},
      builds: [
        ReleaseBuild(
          build: 5,
          runId: 'run_1',
          createdAt: DateTime.utc(2026, 10, 14),
        ),
      ],
      baseBranch: 'main',
      headSha: 'b' * 40,
      prNumber: prNumber,
      createdAt: DateTime.utc(2026, 10, 14),
      updatedAt: DateTime.utc(2026, 10, 14),
    );

    Future<void> open({GitHubPullRequestState? state}) async {
      final pull = await github.createPullRequest(
        _repo,
        title: 't',
        head: 'release/1.2.0',
        base: 'main',
      );
      if (state != null) {
        github.pulls[pull.number] = GitHubPullRequest(
          number: pull.number,
          title: 't',
          state: state,
          headRef: 'release/1.2.0',
          headSha: 'b' * 40,
          baseRef: 'main',
          htmlUrl: pull.htmlUrl,
          mergeCommitSha: state == GitHubPullRequestState.merged
              ? 'd' * 40
              : null,
        );
      }
    }

    setUp(() async {
      releases = InMemoryReleaseRepository();
      await releases.create(release());
      step = GitHubMergePrStep(github: github, releases: releases);
    });

    test('has a side effect and a stored form', () {
      expect(step.kind, 'github.mergePr');
      expect(step.sideEffectOf(input), isTrue);
      expect(step.encodeInput(input), {
        'releaseId': 'rel_1',
        'githubRepoId': 42,
      });
      expect(step.decodeInput(step.encodeInput(input)), input);
      expect(
        () => step.decodeInput({'releaseId': 'rel_1'}),
        throwsFormatException,
      );
      expect(
        () => step.decodeInput({'githubRepoId': 42}),
        throwsFormatException,
      );
    });

    test(
      'merges with a merge commit, and only the commit that was released',
      () async {
        await open();

        final outcome = await step.run(input, context);

        final result = (outcome as StepSucceeded<GitHubMergePrResult>).result;
        expect(result.number, 1);
        expect(result.sha, 'c' * 40);
        expect(result.alreadyMerged, isFalse);
        expect(step.encodeResult(result), {
          'number': 1,
          'sha': 'c' * 40,
          'alreadyMerged': false,
        });
        expect(github.methods, [GitHubMergeMethod.merge]);
        expect(github.expectedHeads, ['b' * 40]);
      },
    );

    test(
      'is done, and does not merge again, when the pull request is merged',
      () async {
        await open(state: GitHubPullRequestState.merged);

        final done = await step.alreadyDone(input, context);
        final outcome = await step.run(input, context);

        expect(done!.sha, 'd' * 40);
        expect(done.alreadyMerged, isTrue);
        expect(
          (outcome as StepSucceeded<GitHubMergePrResult>).result.alreadyMerged,
          isTrue,
        );
        expect(github.methods, isEmpty);
      },
    );

    test(
      'is not done while the pull request is open, or there is none',
      () async {
        await open();
        expect(await step.alreadyDone(input, context), isNull);

        await releases.update(release(prNumber: null));
        expect(await step.alreadyDone(input, context), isNull);
        expect(
          await step.alreadyDone(
            const GitHubMergePrInput(releaseId: 'rel_nope', githubRepoId: 42),
            context,
          ),
          isNull,
        );
      },
    );

    test('takes the pull request when the merge commit is not known', () async {
      await open(state: GitHubPullRequestState.merged);
      github.pulls[1] = GitHubPullRequest(
        number: 1,
        title: 't',
        state: GitHubPullRequestState.merged,
        headRef: 'release/1.2.0',
        headSha: 'b' * 40,
        baseRef: 'main',
        htmlUrl: 'u',
      );

      expect((await step.alreadyDone(input, context))!.sha, 'b' * 40);
    });

    test('merges only once every store is live', () async {
      await open();
      await releases.update(release(state: ReleaseState.approved));

      final outcome = await step.run(input, context);

      expect((outcome as StepFailed).message, contains('is approved'));
      expect(github.methods, isEmpty);
    });

    test('does not merge a pull request that was closed', () async {
      await open(state: GitHubPullRequestState.closed);

      final outcome = await step.run(input, context);

      expect(
        (outcome as StepFailed).message,
        'Pull request #1 was closed without a merge.',
      );
    });

    test('needs a release with a pull request', () async {
      await releases.update(release(prNumber: null));

      final outcome = await step.run(input, context);
      final missing = await step.run(
        const GitHubMergePrInput(releaseId: 'rel_nope', githubRepoId: 42),
        context,
      );

      expect((outcome as StepFailed).message, contains('no pull request'));
      expect((missing as StepFailed).message, contains('rel_nope'));
    });

    test('reports what GitHub said, without choosing another method', () async {
      await open();
      github.mergeFailure = const GitHubNotMergeableException(
        'Merge commits are not allowed on this repository.',
      );

      final outcome = await step.run(input, context);

      expect(
        (outcome as StepFailed).message,
        'GitHub did not merge pull request #1: Merge commits are not allowed '
        'on this repository.',
      );
      expect(github.methods, [GitHubMergeMethod.merge]);
    });
  });
}
