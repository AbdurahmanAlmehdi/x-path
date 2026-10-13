import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

TestRunResults _run(Map<String, TestStatus> tests, {String suite = 'a'}) =>
    TestRunResults.of([
      for (final MapEntry(:key, :value) in tests.entries)
        TestCase(suite: suite, name: key, status: value),
    ]);

TestRef _ref(String name, {String suite = 'a'}) =>
    TestRef(suite: suite, name: name);

void main() {
  const passed = TestStatus.passed;
  const failed = TestStatus.failed;
  const errored = TestStatus.errored;
  const skipped = TestStatus.skipped;

  group('diffTestRuns', () {
    test('a failure the baseline has is not new, even if it changed kind', () {
      final diff = diffTestRuns(
        _run({'x': errored, 'y': failed}),
        _run({'x': failed, 'y': failed}),
      );

      expect(diff.newFailures, isEmpty);
      expect(diff.stillFailing, 2);
    });

    test('a failure of a test that passed or was skipped is new', () {
      final diff = diffTestRuns(
        _run({'x': failed, 'y': errored, 'z': failed}),
        _run({'x': passed, 'y': skipped}),
      );

      expect(diff.newFailures, [_ref('x'), _ref('y'), _ref('z')]);
    });

    test('a test that is not in the baseline and fails is new', () {
      final diff = diffTestRuns(_run({'fresh': failed}), _run({'old': passed}));

      expect(diff.newFailures, [_ref('fresh')]);
    });

    test('fixed means failed in the baseline and passes now', () {
      final diff = diffTestRuns(
        _run({'a1': passed, 'a2': skipped, 'a3': failed}),
        _run({'a1': failed, 'a2': failed, 'a3': errored}),
      );

      expect(diff.fixed, [_ref('a1')]);
      expect(diff.stillFailing, 1);
    });

    test('missing means in the baseline and not in the run', () {
      final diff = diffTestRuns(
        _run({'kept': passed}),
        _run({'kept': passed, 'gone': passed, 'gone failing': failed}),
      );

      expect(diff.missing, [_ref('gone'), _ref('gone failing')]);
      expect(diff.fixed, isEmpty);
    });

    test('a whole file that is gone is missing, unless the run was cut', () {
      final baseline = TestRunResults.of(const [
        TestCase(suite: 'a', name: 't', status: passed),
        TestCase(suite: 'b', name: 't', status: passed),
        TestCase(suite: 'b', name: 'u', status: passed),
      ]);
      final current = _run({'t': passed});

      expect(diffTestRuns(current, baseline).missing, [
        _ref('t', suite: 'b'),
        _ref('u', suite: 'b'),
      ]);
      expect(
        diffTestRuns(
          current,
          baseline,
          expected: ExpectedTests.ranSuites,
        ).missing,
        isEmpty,
      );
      expect(
        diffTestRuns(current, baseline, expected: ExpectedTests.none).missing,
        isEmpty,
      );
    });

    test('a run of some files still misses a test of those files', () {
      final baseline = _run({'t': passed, 'u': passed});

      final diff = diffTestRuns(
        _run({'t': passed}),
        baseline,
        expected: ExpectedTests.ranSuites,
      );

      expect(diff.missing, [_ref('u')]);
    });

    test('orders what it reports by file and name', () {
      final current = TestRunResults.of(const [
        TestCase(suite: 'b', name: 'x', status: failed),
        TestCase(suite: 'a', name: 'z', status: failed),
        TestCase(suite: 'a', name: 'y', status: failed),
      ]);

      expect(diffTestRuns(current, null).newFailures, [
        _ref('y'),
        _ref('z'),
        _ref('x', suite: 'b'),
      ]);
    });
  });
}
