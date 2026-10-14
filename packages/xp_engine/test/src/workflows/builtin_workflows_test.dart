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
      'shorebird-patch',
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
    expect(gates('shorebird-patch'), {GateAction.prodPatch, GateAction.push});
    expect(gates('dev-build'), isEmpty);
    expect(gates('test'), isEmpty);
  });
}
