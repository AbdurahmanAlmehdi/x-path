import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../../helpers/test_engine.dart';
import '../../../helpers/test_run_fakes.dart';

void main() {
  late TestEngine engine;
  late Job job;

  setUp(() async {
    engine = await TestEngine.start();
    job = await engine.createJob(['a']);
  });
  tearDown(() => engine.close());

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  group('GET /jobs/{id}/tests', () {
    setUp(() => engine.testRuns.save(sampleTestRun(job.id)));

    test('shows the run, its diff and the failures', () async {
      final response = await engine.request('/jobs/${job.id}/tests');

      expect(response.statusCode, 200);
      final body = TestRunResponse.fromJson(response.json);
      expect(body.run.id, 'tst_${job.id}');
      expect(body.run.jobId, job.id);
      expect(body.run.counts.total, 5);
      expect(body.run.diff.comparedTo, 'job_0');
      expect(body.run.diff.newFailures, [
        const TestRef(suite: 'test/b_test.dart', name: 'new failure'),
      ]);
      expect(body.run.diff.stillFailing, 1);
      expect(body.total, 2);
      expect(body.tests.map((test) => test.name), [
        'old failure',
        'new failure',
      ]);
      expect(body.tests.first.message, 'Expected: <2>');
      expect(body.tests.first.stackTrace, 'test/a_test.dart 8:7');
    });

    test('lists the statuses asked for', () async {
      final response = await engine.request(
        '/jobs/${job.id}/tests?status=passed,skipped',
      );

      final body = TestRunResponse.fromJson(response.json);
      expect(body.tests.map((test) => test.name), ['a ok', 'b ok', 'later']);
      expect(body.total, 3);
    });

    test('pages through the tests', () async {
      final response = await engine.request(
        '/jobs/${job.id}/tests?status=passed,failed,errored,skipped'
        '&limit=2&offset=1',
      );

      final body = TestRunResponse.fromJson(response.json);
      expect(body.tests.map((test) => test.name), ['b ok', 'old failure']);
      expect(body.total, 5);
      expect(body.offset, 1);
    });

    test('400 for a status, limit or offset that is not valid', () async {
      for (final query in [
        'status=passed,flaky',
        'status=',
        'limit=0',
        'limit=1001',
        'limit=many',
        'offset=-1',
        'offset=x',
      ]) {
        final response = await engine.request('/jobs/${job.id}/tests?$query');

        expect(response.statusCode, 400, reason: query);
        expect(errorCode(response), 'invalid_request');
      }
    });

    test('404 for a job that does not exist', () async {
      final response = await engine.request('/jobs/job_nope/tests');

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });

    test('404 for a job that ran no tests', () async {
      final other = await engine.createJob(['b']);

      final response = await engine.request('/jobs/${other.id}/tests');

      expect(response.statusCode, 404);
      expect(
        response.json['error'],
        containsPair('message', 'Job ${other.id} has no test run.'),
      );
    });

    test('401 without a token', () async {
      final response = await engine.request('/jobs/${job.id}/tests', token: '');

      expect(response.statusCode, 401);
    });
  });

  group('GET /projects/{id}/tests/baseline', () {
    test('lists the current baseline of every app and branch', () async {
      await engine.projectRepository.add(testRunProject());
      final other = await engine.createJob(['b']);
      final newer = await engine.createJob(['c']);
      await engine.testRuns.save(
        sampleTestRun(job.id, baseline: true, createdAt: DateTime.utc(2026, 5)),
      );
      await engine.testRuns.save(
        sampleTestRun(
          newer.id,
          baseline: true,
          createdAt: DateTime.utc(2026, 6),
        ),
      );
      await engine.testRuns.save(
        sampleTestRun(other.id, baseline: true, appPath: 'apps/mobile'),
      );

      final response = await engine.request('/projects/prj_1/tests/baseline');

      expect(response.statusCode, 200);
      final baselines = TestBaselinesResponse.fromJson(response.json).baselines;
      expect(baselines.map((b) => (b.appPath, b.branch, b.jobId)), [
        ('.', 'main', newer.id),
        ('apps/mobile', 'main', other.id),
      ]);
      expect(baselines.first.counts.failed, 1);
      expect(baselines.first.counts.errored, 1);
    });

    test('is empty before a run became the baseline', () async {
      await engine.projectRepository.add(testRunProject());
      await engine.testRuns.save(sampleTestRun(job.id));

      final response = await engine.request('/projects/prj_1/tests/baseline');

      expect(response.json, {'baselines': <Object?>[]});
    });

    test('404 for a project that does not exist', () async {
      final response = await engine.request(
        '/projects/prj_nope/tests/baseline',
      );

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });

    test('401 without a token', () async {
      final response = await engine.request(
        '/projects/prj_1/tests/baseline',
        token: '',
      );

      expect(response.statusCode, 401);
    });
  });
}
