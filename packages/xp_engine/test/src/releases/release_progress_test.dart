import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final at = DateTime.utc(2026, 10, 14, 9);
  var jobs = 0;

  JobProgress job(
    List<(String, StepState, Map<String, dynamic>?)> steps, {
    JobState state = JobState.running,
    String? name,
    String? message,
  }) {
    final id = 'job_${++jobs}';
    return JobProgress(
      JobRecord(
        id: id,
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        state: state,
        name: name,
        message: message,
        createdAt: at,
      ),
      [
        for (final (ordinal, (kind, state, result)) in steps.indexed)
          StepRecord(
            jobId: id,
            ordinal: ordinal,
            kind: kind,
            sideEffect: false,
            input: const {},
            state: state,
            result: result,
          ),
      ],
    );
  }

  group('BuildProgress', () {
    test('reads nothing from jobs that did nothing', () {
      expect(BuildProgress.of(const []), const BuildProgress());
      expect(
        BuildProgress.of([
          job([
            ('git.checkout', StepState.succeeded, null),
            ('build.android', StepState.pending, null),
          ]),
        ]),
        const BuildProgress(),
      );
    });

    test('starts building when a build step starts', () {
      for (final kind in ['build.android', 'build.ios', 'shorebird.release']) {
        expect(
          BuildProgress.of([
            job([(kind, StepState.running, null)]),
          ]).buildStarted,
          isTrue,
          reason: kind,
        );
      }
      expect(
        BuildProgress.of([
          job([('upload.play', StepState.running, null)]),
        ]).buildStarted,
        isFalse,
      );
    });

    test('has uploaded a store when all its upload steps are done', () {
      final progress = BuildProgress.of([
        job([('upload.appStore', StepState.succeeded, {})]),
        job([('upload.play', StepState.succeeded, {})]),
        job([('upload.play', StepState.running, null)]),
      ]);

      expect(progress.uploaded, {ReleaseStore.apple});
    });

    test('counts a skipped upload (already in the store) as done', () {
      final progress = BuildProgress.of([
        job([('upload.appStore', StepState.skipped, {})]),
        job([('upload.play', StepState.failed, null)]),
      ]);

      expect(progress.uploaded, {ReleaseStore.apple});
    });

    test('reads the branch, the tag and the pull request from their steps', () {
      final progress = BuildProgress.of([
        job([
          ('git.releaseBranch', StepState.succeeded, {'name': 'release/1.2.0'}),
        ]),
        job([
          (
            'git.tag',
            StepState.succeeded,
            {'name': 'v1.2.0+5', 'sha': 'b' * 40},
          ),
          (
            'github.createPr',
            StepState.succeeded,
            {'number': 7, 'url': 'https://example/pull/7'},
          ),
        ]),
      ]);

      expect(progress.branch, 'release/1.2.0');
      expect(progress.tag, 'v1.2.0+5');
      expect(progress.headSha, 'b' * 40);
      expect(progress.prNumber, 7);
      expect(progress.prUrl, 'https://example/pull/7');
    });

    test('ignores results of steps that did not succeed', () {
      final progress = BuildProgress.of([
        job([
          ('git.tag', StepState.failed, {'name': 'v1', 'sha': 'x'}),
          ('github.createPr', StepState.running, null),
        ]),
      ]);

      expect(progress.tag, isNull);
      expect(progress.prNumber, isNull);
    });

    test('names the first job that failed or was cancelled', () {
      final failed = BuildProgress.of([
        job([], state: JobState.succeeded),
        job(
          [],
          state: JobState.failed,
          name: 'Build prod for ios',
          message: 'Step 3 failed',
        ),
        job([], state: JobState.cancelled, name: 'Other'),
      ]);
      final cancelled = BuildProgress.of([job([], state: JobState.cancelled)]);

      expect(failed.failure, 'Build prod for ios failed: Step 3 failed');
      expect(cancelled.failure, startsWith('job_'));
      expect(cancelled.failure, endsWith(' cancelled'));
      expect(BuildProgress.of([job([])]).failure, isNull);
    });
  });

  group('MergeProgress', () {
    test('reads the merge commit', () {
      final progress = MergeProgress.of([
        job([
          ('gate', StepState.succeeded, {}),
          ('github.mergePr', StepState.succeeded, {'sha': 'c' * 40}),
        ], state: JobState.succeeded),
      ]);

      expect(progress, MergeProgress(mergeCommit: 'c' * 40));
    });

    test('has ended when a job failed or was cancelled', () {
      final progress = MergeProgress.of([
        job(
          [('gate', StepState.failed, null)],
          state: JobState.failed,
          message: 'denied',
        ),
      ]);

      expect(progress.ended, isTrue);
      expect(progress.failure, 'denied');
      expect(progress.mergeCommit, isNull);
    });

    test('waits while the run waits', () {
      expect(
        MergeProgress.of([
          job([
            ('gate', StepState.waitingForApproval, null),
          ], state: JobState.waitingForApproval),
        ]),
        const MergeProgress(),
      );
    });
  });
}
