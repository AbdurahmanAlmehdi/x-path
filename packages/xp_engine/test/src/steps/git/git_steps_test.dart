import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/scripted_git.dart';
import '../../../helpers/step_context.dart';

const _mirror = GitMirror(githubRepoId: 42, path: '/mirrors/42.git');
const _worktree = ReleaseWorktree(
  path: '/data/worktrees/42/job_2',
  mirror: _mirror,
  sha: 'dispatched',
);
const _head = 'bump';

void main() {
  late ScriptedGit git;
  late InMemoryJobRepository jobs;

  setUp(() {
    git = ScriptedGit()..statusResult = const GitWorktreeStatus(headSha: _head);
    jobs = InMemoryJobRepository();
  });

  group('git.checkout', () {
    late GitCheckoutStep step;

    setUp(() => step = GitCheckoutStep(git: git, jobs: jobs));

    Future<void> prepareJob({
      StepState state = StepState.succeeded,
      Map<String, dynamic>? result = const {'commit': 'bumpsha'},
      String kind = 'version.bump',
    }) async {
      await jobs.create(
        JobRecord(
          id: 'job_1',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.succeeded,
          createdAt: DateTime.utc(2026),
        ),
        [
          const StepRecord(
            jobId: 'job_1',
            ordinal: 0,
            kind: 'guard',
            sideEffect: false,
            input: {},
            state: StepState.succeeded,
          ),
          StepRecord(
            jobId: 'job_1',
            ordinal: 1,
            kind: kind,
            sideEffect: true,
            input: const {},
            state: state,
            result: result,
          ),
        ],
      );
    }

    test('is git.checkout, without a side effect', () {
      expect(step.kind, 'git.checkout');
      expect(
        step.sideEffectOf(const GitCheckoutInput(worktree: _worktree)),
        isFalse,
      );
    });

    test('stores its input and result', () {
      const input = GitCheckoutInput(
        worktree: _worktree,
        commitFromJob: 'job_1',
      );

      expect(step.decodeInput(step.encodeInput(input)), input);
      expect(
        step.encodeInput(const GitCheckoutInput(worktree: _worktree)),
        isNot(contains('commitFromJob')),
      );
      expect(step.encodeResult(const GitCheckoutResult(path: '/p', sha: 's')), {
        'path': '/p',
        'sha': 's',
      });
      expect(const GitCheckoutResult(path: '/p', sha: 's').props, ['/p', 's']);
    });

    test('checks out the dispatched commit', () async {
      final outcome = await step.run(
        const GitCheckoutInput(worktree: _worktree),
        NoProcessContext(),
      );

      expect(
        (outcome as StepSucceeded<GitCheckoutResult>).result,
        const GitCheckoutResult(
          path: '/data/worktrees/42/job_2',
          sha: 'dispatched',
        ),
      );
      expect(git.calls, ['createWorktree job_2 dispatched']);
    });

    test('checks out the version commit of another job', () async {
      await prepareJob();

      final outcome = await step.run(
        const GitCheckoutInput(worktree: _worktree, commitFromJob: 'job_1'),
        NoProcessContext(),
      );

      expect(
        (outcome as StepSucceeded<GitCheckoutResult>).result.sha,
        'bumpsha',
      );
      expect(git.calls, ['createWorktree job_2 bumpsha']);
    });

    test('also takes the commit of a version.bump that was skipped', () async {
      await prepareJob(state: StepState.skipped);

      final outcome = await step.run(
        const GitCheckoutInput(worktree: _worktree, commitFromJob: 'job_1'),
        NoProcessContext(),
      );

      expect(outcome, isA<StepSucceeded<GitCheckoutResult>>());
    });

    test('fails when the other job made no version commit', () async {
      await prepareJob(state: StepState.failed, result: null);

      for (final source in ['job_1', 'job_missing']) {
        final outcome = await step.run(
          GitCheckoutInput(worktree: _worktree, commitFromJob: source),
          NoProcessContext(),
        );

        expect(
          (outcome as StepFailed).message,
          'Job $source made no version commit, so this job has nothing to '
          'start from.',
        );
      }
      expect(git.calls, isEmpty);
    });

    test(
      'fails when the worktree is not where the steps look for it',
      () async {
        git.worktreePath = '/elsewhere/job_2';

        final outcome = await step.run(
          const GitCheckoutInput(worktree: _worktree),
          NoProcessContext(),
        );

        expect(
          (outcome as StepFailed).message,
          'The worktree is at /elsewhere/job_2, not at '
          '/data/worktrees/42/job_2 where the steps of this job look for it.',
        );
      },
    );
  });

  group('git.tag', () {
    late GitTagStep step;
    const input = GitTagInput(
      worktree: _worktree,
      name: 'v1.2.3+45',
      message: 'Release 1.2.3+45',
    );

    setUp(() => step = GitTagStep(git));

    test('is git.tag, with a side effect', () {
      expect(step.kind, 'git.tag');
      expect(step.sideEffectOf(input), isTrue);
    });

    test('stores its input and result', () {
      expect(step.decodeInput(step.encodeInput(input)), input);
      expect(
        step.encodeResult(
          const GitTagResult(name: 't', sha: 's', reused: true),
        ),
        {'name': 't', 'sha': 's', 'reused': true},
      );
      expect(const GitTagResult(name: 't', sha: 's', reused: false).props, [
        't',
        's',
        false,
      ]);
    });

    test('tags the head of the worktree', () async {
      final outcome = await step.run(input, NoProcessContext());

      expect(
        (outcome as StepSucceeded<GitTagResult>).result,
        const GitTagResult(name: 'v1.2.3+45', sha: _head, reused: false),
      );
      expect(git.tags, {'v1.2.3+45': _head});
    });

    test('reuses a tag on the same commit', () async {
      git.tags['v1.2.3+45'] = _head;

      final outcome = await step.run(input, NoProcessContext());

      expect((outcome as StepSucceeded<GitTagResult>).result.reused, isTrue);
    });

    test('fails for a tag on another commit, never moving it', () async {
      git.tags['v1.2.3+45'] = 'other';

      final outcome = await step.run(input, NoProcessContext());

      expect(
        (outcome as StepFailed).message,
        'Tag v1.2.3+45 is on other, not on bump.',
      );
      expect(git.tags['v1.2.3+45'], 'other');
    });

    test('is done when the tag names the head already', () async {
      expect(await step.alreadyDone(input, NoProcessContext()), isNull);

      git.tags['v1.2.3+45'] = 'other';
      expect(await step.alreadyDone(input, NoProcessContext()), isNull);

      git.tags['v1.2.3+45'] = _head;
      expect(
        await step.alreadyDone(input, NoProcessContext()),
        const GitTagResult(name: 'v1.2.3+45', sha: _head, reused: true),
      );
    });
  });

  group('git.releaseBranch', () {
    late GitReleaseBranchStep step;
    final input = GitReleaseBranchInput(
      worktree: _worktree,
      version: VersionName.parse('1.2.3'),
    );

    setUp(() => step = GitReleaseBranchStep(git));

    test('is git.releaseBranch, with a side effect', () {
      expect(step.kind, 'git.releaseBranch');
      expect(step.sideEffectOf(input), isTrue);
    });

    test('stores its input and result', () {
      expect(step.decodeInput(step.encodeInput(input)), input);
      expect(
        step.encodeResult(
          const GitReleaseBranchResult(
            name: 'release/1.2.3',
            outcome: BranchOutcome.updated,
          ),
        ),
        {'name': 'release/1.2.3', 'outcome': 'updated'},
      );
      expect(
        const GitReleaseBranchResult(
          name: 'b',
          outcome: BranchOutcome.created,
        ).props,
        ['b', BranchOutcome.created],
      );
    });

    test('refuses a version that is not x.y.z', () {
      expect(
        () => GitReleaseBranchInput.fromJson({
          'worktree': _worktree.toJson(),
          'version': '1.2',
        }),
        throwsFormatException,
      );
    });

    test('cuts the branch at the head of the worktree', () async {
      final outcome = await step.run(input, NoProcessContext());

      expect(
        (outcome as StepSucceeded<GitReleaseBranchResult>).result,
        const GitReleaseBranchResult(
          name: 'release/1.2.3',
          outcome: BranchOutcome.created,
        ),
      );
      expect(git.branches, {'release/1.2.3': _head});
    });

    test('says the branch is there when it is', () async {
      git.branches['release/1.2.3'] = _head;

      final outcome = await step.run(input, NoProcessContext());

      expect(
        (outcome as StepSucceeded<GitReleaseBranchResult>).result.outcome,
        BranchOutcome.unchanged,
      );
    });

    test('fails when the branch cannot move forward to the head', () async {
      git.branches['release/1.2.3'] = 'elsewhere';

      final outcome = await step.run(input, NoProcessContext());

      expect(
        (outcome as StepFailed).message,
        'Branch release/1.2.3 is on elsewhere; bump is not a descendant of '
        'it.',
      );
    });
  });

  group('git.push', () {
    late GitPushStep step;
    const input = GitPushInput(
      worktree: _worktree,
      branch: 'release/1.2.3',
      tag: 'v1.2.3+45',
    );

    setUp(() => step = GitPushStep(git));

    test('is git.push, with a side effect', () {
      expect(step.kind, 'git.push');
      expect(step.sideEffectOf(input), isTrue);
    });

    test('stores its input and result', () {
      expect(step.decodeInput(step.encodeInput(input)), input);
      expect(step.encodeResult(const GitPushResult(['r'])), {
        'refspecs': ['r'],
      });
      expect(const GitPushResult(['r']).props, [
        ['r'],
      ]);
      expect(
        step.encodeInput(const GitPushInput(worktree: _worktree, tag: 'v1')),
        isNot(contains('branch')),
      );
    });

    test('needs a branch or a tag', () {
      expect(
        () => GitPushInput.fromJson({'worktree': _worktree.toJson()}),
        throwsFormatException,
      );
    });

    test('pushes the branch and the tag, never forced', () async {
      final outcome = await step.run(input, NoProcessContext());

      final refspecs = [
        'refs/heads/release/1.2.3:refs/heads/release/1.2.3',
        'refs/tags/v1.2.3+45:refs/tags/v1.2.3+45',
      ];
      expect(
        (outcome as StepSucceeded<GitPushResult>).result.refspecs,
        refspecs,
      );
      expect(git.pushed, [refspecs]);
      expect(input.refspecs.any((spec) => spec.startsWith('+')), isFalse);
    });

    test('pushes a tag alone', () async {
      await step.run(
        const GitPushInput(worktree: _worktree, tag: 'v1'),
        NoProcessContext(),
      );

      expect(git.pushed.single, ['refs/tags/v1:refs/tags/v1']);
    });

    test('fails when the remote refuses', () async {
      git.pushFailure = const GitPushRejectedException(
        'rejected: not a fast-forward',
      );

      final outcome = await step.run(input, NoProcessContext());

      expect((outcome as StepFailed).message, 'rejected: not a fast-forward');
    });
  });
}
