import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

TestCase _test(
  String name,
  TestStatus status, {
  String suite = 'test/a_test.dart',
  String? message,
  String? stackTrace,
}) => TestCase(
  suite: suite,
  name: name,
  status: status,
  message: message,
  stackTrace: stackTrace,
);

void main() {
  group('TestRunResults', () {
    test('orders the tests by file and name', () {
      final results = TestRunResults.of([
        _test('b', TestStatus.passed),
        _test('a', TestStatus.passed, suite: 'test/z_test.dart'),
        _test('a', TestStatus.passed),
      ]);

      expect(
        [for (final test in results.tests) '${test.suite} ${test.name}'],
        ['test/a_test.dart a', 'test/a_test.dart b', 'test/z_test.dart a'],
      );
      expect(results.suites, {'test/a_test.dart', 'test/z_test.dart'});
    });

    test('counts one test for a name that occurs twice, the worse wins', () {
      final results = TestRunResults.of([
        _test('twin', TestStatus.passed),
        _test('twin', TestStatus.failed, message: 'first'),
        _test('twin', TestStatus.errored, message: 'worst'),
        _test('twin', TestStatus.failed, message: 'again'),
        _test('other', TestStatus.skipped),
        _test('other', TestStatus.passed),
      ]);

      expect(results.tests, [
        _test('other', TestStatus.passed),
        _test('twin', TestStatus.errored, message: 'worst'),
      ]);
    });

    test('keeps the first of two failures of the same weight', () {
      final results = TestRunResults.of([
        _test('twin', TestStatus.failed, message: 'first'),
        _test('twin', TestStatus.failed, message: 'second'),
      ]);

      expect(results.tests.single.message, 'first');
    });

    test('finds a test by identity', () {
      final results = TestRunResults.of([_test('a', TestStatus.passed)]);

      expect(
        results[const TestRef(suite: 'test/a_test.dart', name: 'a')],
        isNotNull,
      );
      expect(
        results[const TestRef(suite: 'test/a_test.dart', name: 'b')],
        isNull,
      );
    });

    test('counts every status and lists the failures', () {
      final results = TestRunResults.of([
        _test('1', TestStatus.passed),
        _test('2', TestStatus.passed),
        _test('3', TestStatus.failed),
        _test('4', TestStatus.errored),
        _test('5', TestStatus.skipped),
      ]);

      expect(
        results.counts,
        const TestCounts(
          total: 5,
          passed: 2,
          failed: 1,
          errored: 1,
          skipped: 1,
        ),
      );
      expect(results.failures.map((test) => test.name), ['3', '4']);
    });

    test('stores a passing test as its name only', () {
      final results = TestRunResults.of([
        _test('ok', TestStatus.passed),
        _test('later', TestStatus.skipped),
        _test(
          'bad',
          TestStatus.failed,
          message: 'Expected 1',
          stackTrace: 'a.dart 1:1',
        ),
        _test('worse', TestStatus.errored),
      ]);

      expect(results.toJson(), {
        'suites': {
          'test/a_test.dart': {
            'errored': [
              {'name': 'worse'},
            ],
            'failed': [
              {
                'name': 'bad',
                'message': 'Expected 1',
                'stackTrace': 'a.dart 1:1',
              },
            ],
            'passed': ['ok'],
            'skipped': ['later'],
          },
        },
      });
    });

    test('reads what it wrote', () {
      final results = TestRunResults.of([
        _test('ok', TestStatus.passed, suite: 'test/b_test.dart'),
        _test('skip', TestStatus.skipped),
        _test('bad', TestStatus.failed, message: 'm', stackTrace: 's'),
        _test('worse', TestStatus.errored),
      ]);

      expect(TestRunResults.fromJson(results.toJson()), results);
    });

    test('refuses stored results that are not valid', () {
      for (final bad in <Map<String, dynamic>>[
        {},
        {'suites': <String>[]},
        {
          'suites': {'a': 3},
        },
        {
          'suites': {
            'a': {'passed': 'x'},
          },
        },
        {
          'suites': {
            'a': {
              'passed': [3],
            },
          },
        },
        {
          'suites': {
            'a': {
              'failed': ['plain'],
            },
          },
        },
        {
          'suites': {
            'a': {
              'failed': [
                {'message': 'no name'},
              ],
            },
          },
        },
      ]) {
        expect(
          () => TestRunResults.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('is small for a large run', () {
      final results = TestRunResults.of([
        for (var i = 0; i < 5000; i++)
          _test('test number $i', TestStatus.passed),
      ]);

      // A name and a separator per test, the file once.
      expect(results.toJson().toString().length, lessThan(5000 * 24));
    });
  });
}
