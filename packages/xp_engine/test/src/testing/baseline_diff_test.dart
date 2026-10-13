import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/testing_fixtures.dart';

/// Phase 9d acceptance: a captured run with 27 pre-existing failures
/// (`flutter test --machine` on a throwaway app) is the baseline, and a later
/// run of the same app reports only what is new.
void main() {
  late TestRunResults baseline;
  late TestRunResults branch;

  setUp(() {
    baseline = parseCapturedRun('baseline_27_failures.jsonl').results;
    branch = parseCapturedRun('branch_run.jsonl').results;
  });

  TestRef ref(String suite, String name) => TestRef(suite: suite, name: name);

  test('the baseline has the 27 failures that were there all along', () {
    expect(baseline.failures, hasLength(27));
  });

  test('reports only the new failures of the branch', () {
    final diff = diffTestRuns(branch, baseline, comparedTo: 'job_base');

    expect(diff.newFailures, [
      ref('test/async_test.dart', 'async success 5'),
      ref('test/math_test.dart', 'subtraction subtracts one'),
      ref('test/math_test.dart', 'subtraction subtracts two'),
    ]);
    expect(branch.failures, hasLength(29));
    expect(diff.stillFailing, 26);
    expect(diff.comparedTo, 'job_base');
  });

  test('reports the failure that was fixed and the test that is gone', () {
    final diff = diffTestRuns(branch, baseline);

    expect(diff.fixed, [ref('test/math_test.dart', 'arithmetic adds 3')]);
    expect(diff.missing, [ref('test/strings_test.dart', 'strings trims 6')]);
  });

  test('the baseline compared with itself has nothing new', () {
    final diff = diffTestRuns(baseline, baseline);

    expect(diff.newFailures, isEmpty);
    expect(diff.fixed, isEmpty);
    expect(diff.missing, isEmpty);
    expect(diff.stillFailing, 27);
  });

  test('without a baseline every failure is new', () {
    final diff = diffTestRuns(baseline, null);

    expect(diff.newFailures, hasLength(27));
    expect(diff.stillFailing, 0);
    expect(diff.comparedTo, isNull);
  });

  test('the branch run fails the step, the base-branch run seeds', () {
    final onBranch = evaluateTestRun(
      results: branch,
      baseline: _record(baseline),
      onBaseBranch: false,
      filtered: false,
      expected: ExpectedTests.all,
    );
    final seeding = evaluateTestRun(
      results: baseline,
      baseline: null,
      onBaseBranch: true,
      filtered: false,
      expected: ExpectedTests.all,
    );

    expect(onBranch.failsStep, isTrue);
    expect(onBranch.becomesBaseline, isFalse);
    expect(seeding.failsStep, isFalse);
    expect(seeding.becomesBaseline, isTrue);
    expect(seeding.seeded, isTrue);
  });

  test('survives being stored and read back', () {
    final stored = TestRunResults.fromJson(_record(branch).results.toJson());

    expect(diffTestRuns(stored, baseline).newFailures, hasLength(3));
  });
}

TestRunRecord _record(TestRunResults results) => TestRunRecord(
  id: 'tst_1',
  jobId: 'job_base',
  projectId: 'prj_1',
  branch: 'main',
  appPath: '.',
  baseline: true,
  createdAt: DateTime.utc(2026, 10, 13),
  results: results,
  diff: diffTestRuns(results, null),
);
