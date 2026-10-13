import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/test_run_records.dart';

void main() {
  final record = testRunRecord(branch: 'feat/x', appPath: 'apps/mobile');

  test('is stored as columns and one JSON document', () {
    final stored = record.resultsJson();

    expect(stored.keys, containsAll(['suites', 'diff']));
    expect(
      TestRunRecord.fromStored(
        id: record.id,
        jobId: record.jobId,
        projectId: record.projectId,
        branch: record.branch,
        appPath: record.appPath,
        baseline: record.baseline,
        createdAt: record.createdAt,
        stored: stored,
      ),
      record,
    );
  });

  test('refuses a stored document without a diff', () {
    expect(
      () => TestRunRecord.fromStored(
        id: 'tst_1',
        jobId: 'job_1',
        projectId: 'prj_1',
        branch: 'main',
        appPath: '.',
        baseline: true,
        createdAt: DateTime.utc(2026),
        stored: const {'suites': <String, dynamic>{}},
      ),
      throwsFormatException,
    );
  });

  test('shows as an API run', () {
    final run = record.toTestRun();

    expect(run.id, 'tst_1');
    expect(run.jobId, 'job_1');
    expect(run.branch, 'feat/x');
    expect(run.appPath, 'apps/mobile');
    expect(run.baseline, isTrue);
    expect(run.counts.failed, 1);
    expect(run.diff, record.diff);
  });

  test('shows as an API baseline', () {
    expect(
      record.toTestBaseline(),
      TestBaseline(
        appPath: 'apps/mobile',
        branch: 'feat/x',
        jobId: 'job_1',
        createdAt: DateTime.utc(2026, 10, 13),
        counts: record.results.counts,
      ),
    );
  });
}
