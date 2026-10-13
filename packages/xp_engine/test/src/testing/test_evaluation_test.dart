import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

TestRunResults _run(Map<String, TestStatus> tests) => TestRunResults.of([
  for (final MapEntry(:key, :value) in tests.entries)
    TestCase(suite: 'a', name: key, status: value),
]);

TestRunRecord _baseline(Map<String, TestStatus> tests) {
  final results = _run(tests);
  return TestRunRecord(
    id: 'tst_base',
    jobId: 'job_base',
    projectId: 'prj_1',
    branch: 'main',
    appPath: '.',
    baseline: true,
    createdAt: DateTime.utc(2026),
    results: results,
    diff: diffTestRuns(results, null),
  );
}

TestEvaluation _evaluate(
  Map<String, TestStatus> tests, {
  TestRunRecord? baseline,
  bool onBaseBranch = true,
  bool filtered = false,
}) => evaluateTestRun(
  results: _run(tests),
  baseline: baseline,
  onBaseBranch: onBaseBranch,
  filtered: filtered,
  expected: ExpectedTests.all,
);

void main() {
  const passed = TestStatus.passed;
  const failed = TestStatus.failed;

  group('evaluateTestRun', () {
    test('the first run of the base branch seeds the baseline as it is', () {
      final evaluation = _evaluate({'ok': passed, 'bad': failed});

      expect(evaluation.seeded, isTrue);
      expect(evaluation.becomesBaseline, isTrue);
      expect(evaluation.failsStep, isFalse);
      expect(evaluation.diff.newFailures, hasLength(1));
    });

    test('a green run of the base branch replaces the baseline', () {
      final evaluation = _evaluate({
        'ok': passed,
        'bad': failed,
      }, baseline: _baseline({'ok': passed, 'bad': failed}));

      expect(evaluation.seeded, isFalse);
      expect(evaluation.becomesBaseline, isTrue);
      expect(evaluation.failsStep, isFalse);
      expect(evaluation.diff.comparedTo, 'job_base');
    });

    test('a base-branch run that fixed failures raises the baseline', () {
      final evaluation = _evaluate({
        'ok': passed,
        'bad': passed,
      }, baseline: _baseline({'ok': passed, 'bad': failed}));

      expect(evaluation.becomesBaseline, isTrue);
      expect(evaluation.diff.fixed, hasLength(1));
    });

    test('a base-branch run with new failures fails and is no baseline', () {
      final evaluation = _evaluate({
        'ok': failed,
        'bad': failed,
      }, baseline: _baseline({'ok': passed, 'bad': failed}));

      expect(evaluation.failsStep, isTrue);
      expect(evaluation.becomesBaseline, isFalse);
    });

    test('a branch run never becomes the baseline', () {
      final evaluation = _evaluate(
        {'ok': passed},
        baseline: _baseline({'ok': passed}),
        onBaseBranch: false,
      );

      expect(evaluation.becomesBaseline, isFalse);
      expect(evaluation.failsStep, isFalse);
    });

    test('a branch run without a baseline fails on any failure', () {
      final evaluation = _evaluate({
        'ok': passed,
        'bad': failed,
      }, onBaseBranch: false);

      expect(evaluation.seeded, isFalse);
      expect(evaluation.failsStep, isTrue);
    });

    test('a branch run without a baseline and without failures passes', () {
      final evaluation = _evaluate({'ok': passed}, onBaseBranch: false);

      expect(evaluation.failsStep, isFalse);
      expect(evaluation.becomesBaseline, isFalse);
    });

    test('a run of some files or tags is never a baseline or a seed', () {
      final seeding = _evaluate({'bad': failed}, filtered: true);
      final green = _evaluate(
        {'ok': passed},
        baseline: _baseline({'ok': passed}),
        filtered: true,
      );

      expect(seeding.seeded, isFalse);
      expect(seeding.becomesBaseline, isFalse);
      expect(seeding.failsStep, isTrue);
      expect(green.becomesBaseline, isFalse);
    });
  });
}
