import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);
  const counts = TestCounts(
    total: 10,
    passed: 6,
    failed: 2,
    errored: 1,
    skipped: 1,
  );
  const diff = TestRunDiff(
    comparedTo: 'job_0',
    newFailures: [TestRef(suite: 'test/a_test.dart', name: 'g new')],
    fixed: [TestRef(suite: 'test/a_test.dart', name: 'g fixed')],
    missing: [TestRef(suite: 'test/b_test.dart', name: 'gone')],
    stillFailing: 2,
  );
  final run = TestRun(
    id: 'tst_1',
    jobId: 'job_1',
    branch: 'main',
    appPath: 'apps/mobile',
    baseline: true,
    createdAt: created,
    counts: counts,
    diff: diff,
  );

  group('TestStatus', () {
    test('has the wire names of the stored form', () {
      expect(TestStatus.values.map((status) => status.wire), [
        'passed',
        'failed',
        'errored',
        'skipped',
      ]);
    });

    test('counts a failed expectation and a throw as failures', () {
      expect(TestStatus.values.where((status) => status.isFailure), [
        TestStatus.failed,
        TestStatus.errored,
      ]);
    });
  });

  group('TestRef', () {
    test('compares by value and round-trips', () {
      const ref = TestRef(suite: 'test/a_test.dart', name: 'group name');

      expect(TestRef.fromJson(ref.toJson()), ref);
      expect(ref.toJson(), {'suite': 'test/a_test.dart', 'name': 'group name'});
    });
  });

  group('TestCase', () {
    test('serializes a failure with its message and stack', () {
      const failure = TestCase(
        suite: 'test/a_test.dart',
        name: 'g t',
        status: TestStatus.failed,
        message: 'Expected: <2>',
        stackTrace: 'test/a_test.dart 8:7',
      );

      expect(failure.toJson(), {
        'suite': 'test/a_test.dart',
        'name': 'g t',
        'status': 'failed',
        'message': 'Expected: <2>',
        'stackTrace': 'test/a_test.dart 8:7',
      });
      expect(TestCase.fromJson(failure.toJson()), failure);
      expect(
        failure.ref,
        const TestRef(suite: 'test/a_test.dart', name: 'g t'),
      );
    });

    test('leaves out what a passing test does not have', () {
      const passing = TestCase(
        suite: 'test/a_test.dart',
        name: 'g t',
        status: TestStatus.passed,
      );

      expect(passing.toJson().keys, ['suite', 'name', 'status']);
    });
  });

  test('TestCounts round-trips', () {
    expect(TestCounts.fromJson(counts.toJson()), counts);
    expect(counts.toJson()['errored'], 1);
  });

  group('TestRunDiff', () {
    test('round-trips and names the baseline it was compared with', () {
      expect(TestRunDiff.fromJson(diff.toJson()), diff);
      expect(diff.toJson()['comparedTo'], 'job_0');
      expect(diff.toJson()['newFailures'], [
        {'suite': 'test/a_test.dart', 'name': 'g new'},
      ]);
    });

    test('leaves out the baseline when there was none', () {
      const none = TestRunDiff(
        newFailures: [],
        fixed: [],
        missing: [],
        stillFailing: 0,
      );

      expect(none.toJson().containsKey('comparedTo'), isFalse);
      expect(TestRunDiff.fromJson(none.toJson()), none);
    });
  });

  test('TestRun serializes every field and round-trips', () {
    expect(run.toJson(), {
      'id': 'tst_1',
      'jobId': 'job_1',
      'branch': 'main',
      'appPath': 'apps/mobile',
      'baseline': true,
      'createdAt': '2026-10-13T09:00:00.000Z',
      'counts': counts.toJson(),
      'diff': diff.toJson(),
    });
    expect(TestRun.fromJson(run.toJson()), run);
  });

  test('TestRunResponse holds a page of tests', () {
    final response = TestRunResponse(
      run: run,
      total: 1,
      offset: 0,
      tests: const [
        TestCase(
          suite: 'test/a_test.dart',
          name: 'g t',
          status: TestStatus.errored,
          message: 'boom',
        ),
      ],
    );

    final json = response.toJson();

    expect((json['tests']! as List).single, isA<Map<String, dynamic>>());
    expect(json['total'], 1);
    expect(json['offset'], 0);
    expect(TestRunResponse.fromJson(json), response);
  });

  test('TestBaselinesResponse lists the baselines inline', () {
    final baseline = TestBaseline(
      appPath: 'apps/mobile',
      branch: 'main',
      jobId: 'job_1',
      createdAt: created,
      counts: counts,
    );
    final response = TestBaselinesResponse([baseline]);

    final json = response.toJson();

    expect(baseline.toJson()['createdAt'], '2026-10-13T09:00:00.000Z');
    expect((json['baselines']! as List).single, isA<Map<String, dynamic>>());
    expect(TestBaseline.fromJson(baseline.toJson()), baseline);
    expect(TestBaselinesResponse.fromJson(json), response);
  });
}
