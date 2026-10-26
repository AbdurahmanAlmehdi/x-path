import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/all_steps.dart';

void main() {
  final parser = WorkflowParser(StepPlanners(allSteps()));

  test('are the four of the plan and the merge of a release', () {
    expect(builtinWorkflows.keys, [
      'dev-build',
      'prod-release',
      'release-merge',
      'release-rollout',
      'shorebird-patch',
      'smoke-build',
      'test',
    ]);
  });

  for (final MapEntry(key: name, value: yaml) in builtinWorkflows.entries) {
    test('$name is a valid workflow', () {
      final result = parser.parse(yaml);

      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.definition!.name, isNotEmpty);
    });
  }

  test(
    'prod-release and shorebird-patch lock the project, the others do not',
    () {
      bool locks(String name) =>
          parser.parse(builtinWorkflows[name]!).definition!.locksProject;

      expect(locks('prod-release'), isTrue);
      expect(locks('shorebird-patch'), isTrue);
      expect(locks('dev-build'), isFalse);
      expect(locks('release-merge'), isFalse);
      expect(locks('release-rollout'), isFalse);
      expect(locks('smoke-build'), isFalse);
      expect(locks('test'), isFalse);
    },
  );

  test('gate the actions of D-13 that they can reach', () {
    Set<GateAction> gates(String name) => {
      for (final job in parser.parse(builtinWorkflows[name]!).definition!.jobs)
        for (final step in job.steps)
          if (step.gate != null) step.gate!,
    };

    expect(gates('prod-release'), {GateAction.prodRelease, GateAction.push});
    expect(gates('release-merge'), {GateAction.merge});
    expect(gates('release-rollout'), {GateAction.rollout});
    expect(gates('shorebird-patch'), {GateAction.prodPatch, GateAction.push});
    expect(gates('dev-build'), isEmpty);
    expect(gates('smoke-build'), isEmpty);
    expect(gates('test'), isEmpty);
  });

  test('keep the engine-only steps out of the jobs that build (ADR 0010)', () {
    for (final name in [
      'dev-build',
      'prod-release',
      'shorebird-patch',
      'smoke-build',
    ]) {
      final jobs = parser.parse(builtinWorkflows[name]!).definition!.jobs;
      var builds = 0;
      for (final job in jobs) {
        final kinds = [for (final step in job.steps) step.kind];
        final building = kinds.any(
          (kind) =>
              kind.startsWith('build.') ||
              kind.startsWith('shorebird.') ||
              kind == 'symbols.archive',
        );
        if (building) {
          builds++;
          expect(
            RemoteStepPolicy.engineOnlyIn(kinds),
            isEmpty,
            reason: '$name ${job.id}',
          );
        }
      }
      expect(builds, 1, reason: '$name has one job that builds');
    }
  });

  test(
    'smoke-build builds an APK without the keystore and uploads nothing',
    () {
      final jobs = parser
          .parse(builtinWorkflows['smoke-build']!)
          .definition!
          .jobs;
      final steps = [for (final job in jobs) ...job.steps];

      expect(
        [for (final step in steps) step.kind],
        ['git.checkout', 'build.android'],
      );
      expect(steps.last.withValues, containsPair('keystore', false));
    },
  );

  test('cut the release branch and push it before anything is built', () {
    final jobs = parser
        .parse(builtinWorkflows['prod-release']!)
        .definition!
        .jobs;
    final kinds = [for (final step in jobs.first.steps) step.kind];

    expect(jobs.first.id, 'prepare');
    expect(kinds, containsAllInOrder(['git.releaseBranch', 'git.push']));
  });
}
