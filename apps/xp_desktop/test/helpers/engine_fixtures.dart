import 'package:xp_api/xp_api.dart';

import 'pump_app.dart';

// The sample data of PRODUCT.md §9 for the tests, runners and storage views.

final _paired = DateTime.utc(2026, 10, 1, 9);

/// "This Mac"-like runner holding one job of three slots.
final busyRunner = Runner(
  id: 'rnr_1',
  name: 'mac-mini',
  status: RunnerStatus.online,
  capabilities: const ['ios-sign', 'android', 'flutter'],
  slots: 3,
  jobIds: const ['job_ios'],
  os: 'macos',
  arch: 'arm64',
  version: '1.0.0',
  cores: 12,
  lastHeartbeat: testNow.subtract(const Duration(seconds: 15)),
  createdAt: _paired,
);

/// An idle Linux runner.
final idleRunner = Runner(
  id: 'rnr_2',
  name: 'linux-builder-01',
  status: RunnerStatus.online,
  capabilities: const ['android', 'flutter', 'swift-linux'],
  slots: 4,
  jobIds: const [],
  os: 'linux',
  arch: 'x64',
  version: '1.0.0',
  cores: 16,
  lastHeartbeat: testNow.subtract(const Duration(hours: 2, minutes: 3)),
  createdAt: _paired,
);

/// A runner that dropped off while it held a job.
final lostRunner = Runner(
  id: 'rnr_3',
  name: 'old-mac',
  status: RunnerStatus.offline,
  capabilities: const [],
  slots: 1,
  jobIds: const ['job_lost'],
  lastHeartbeat: testNow.subtract(const Duration(minutes: 4)),
  createdAt: _paired,
);

/// A runner that was revoked.
final revokedRunner = Runner(
  id: 'rnr_4',
  name: 'retired',
  status: RunnerStatus.revoked,
  capabilities: const [],
  slots: 1,
  jobIds: const [],
  createdAt: _paired,
  revokedAt: DateTime.utc(2026, 10, 10, 8),
);

/// The storage of the sample: 51.2 GB, 38.9 GB reclaimable.
final storageReport = StorageReport(
  generatedAt: DateTime.utc(2026, 10, 13, 12, 2),
  categories: const [
    CategoryUsage(
      category: StorageCategory.artifacts,
      usedBytes: 41200000000,
      reclaimableBytes: 33100000000,
      items: 214,
    ),
    CategoryUsage(
      category: StorageCategory.logs,
      usedBytes: 1800000000,
      reclaimableBytes: 600000000,
      items: 902,
    ),
    CategoryUsage(
      category: StorageCategory.worktrees,
      usedBytes: 5200000000,
      reclaimableBytes: 5200000000,
      items: 6,
    ),
    CategoryUsage(
      category: StorageCategory.mirrors,
      usedBytes: 0,
      reclaimableBytes: 0,
      items: 0,
    ),
    CategoryUsage(
      category: StorageCategory.flutter,
      usedBytes: 3000000000,
      reclaimableBytes: 0,
      items: 2,
    ),
  ],
  flavors: const [
    FlavorUsage(
      projectId: 'prj_1',
      app: '.',
      flavor: 'prod',
      builds: 18,
      artifacts: 74,
      usedBytes: 29400000000,
      reclaimableBytes: 23800000000,
    ),
    FlavorUsage(
      projectId: 'prj_9',
      app: 'apps/guest',
      flavor: '',
      builds: 1,
      artifacts: 2,
      usedBytes: 812000000,
      reclaimableBytes: 0,
    ),
  ],
  retention: const RetentionSettings(),
);

const _counts = TestCounts(
  total: 1314,
  passed: 1284,
  failed: 26,
  errored: 1,
  skipped: 3,
);

/// The baseline of `main`.
final mainBaseline = TestBaseline(
  appPath: '.',
  branch: 'main',
  jobId: 'job_base',
  createdAt: DateTime.utc(2026, 10, 12, 18, 30),
  counts: _counts,
);

/// An older baseline of a release branch.
final releaseBaseline = TestBaseline(
  appPath: 'apps/captain',
  branch: 'release/5.4.1',
  jobId: 'job_rel',
  createdAt: DateTime.utc(2026, 10, 11, 9),
  counts: _counts,
);

const _newFailure = TestRef(
  suite: 'test/cart/cart_test.dart',
  name: 'cart totals include the delivery fee',
);

/// A run of `dev` against the `main` baseline: one new failure, one still
/// failing, three fixed, one not reported.
final devRun = TestRunResponse(
  run: TestRun(
    id: 'tst_1',
    jobId: 'job_dev',
    branch: 'dev',
    appPath: '.',
    baseline: false,
    createdAt: DateTime.utc(2026, 10, 13, 11, 50),
    counts: _counts,
    diff: const TestRunDiff(
      comparedTo: 'job_base',
      newFailures: [_newFailure],
      fixed: [
        TestRef(suite: 'test/a_test.dart', name: 'a fixed one'),
        TestRef(suite: 'test/a_test.dart', name: 'a second fixed one'),
        TestRef(suite: 'test/b_test.dart', name: 'a third fixed one'),
      ],
      missing: [TestRef(suite: 'test/gone_test.dart', name: 'a removed test')],
      stillFailing: 1,
    ),
  ),
  total: 2,
  offset: 0,
  tests: const [
    TestCase(
      suite: 'test/cart/cart_test.dart',
      name: 'cart totals include the delivery fee',
      status: TestStatus.failed,
      message: 'Expected: <12.5>\n  Actual: <10.0>',
    ),
    TestCase(
      suite: 'test/map/map_test.dart',
      name: 'map loads tiles offline',
      status: TestStatus.errored,
      message: 'SocketException: Failed host lookup',
    ),
  ],
);

/// The baseline run itself, nothing changed.
final baselineRun = TestRunResponse(
  run: TestRun(
    id: 'tst_0',
    jobId: 'job_base',
    branch: 'main',
    appPath: '.',
    baseline: true,
    createdAt: DateTime.utc(2026, 10, 12, 18, 30),
    counts: const TestCounts(
      total: 10,
      passed: 10,
      failed: 0,
      errored: 0,
      skipped: 0,
    ),
    diff: const TestRunDiff(
      newFailures: [],
      fixed: [],
      missing: [],
      stillFailing: 0,
    ),
  ),
  total: 0,
  offset: 0,
  tests: const [],
);

/// The job that ran [devRun], its test step 2m 41s.
final devJob = Job(
  id: 'job_dev',
  projectId: 'prj_1',
  workflowVersionId: 'wfv_1',
  runId: 'run_tests',
  state: JobState.succeeded,
  createdAt: DateTime.utc(2026, 10, 13, 11, 45),
  steps: [
    JobStep(
      ordinal: 0,
      kind: 'git.checkout',
      state: StepState.succeeded,
      sideEffect: false,
      attempts: 1,
      startedAt: DateTime.utc(2026, 10, 13, 11, 46),
      finishedAt: DateTime.utc(2026, 10, 13, 11, 47),
    ),
    JobStep(
      ordinal: 1,
      kind: 'test',
      state: StepState.succeeded,
      sideEffect: false,
      attempts: 1,
      startedAt: DateTime.utc(2026, 10, 13, 11, 47, 9),
      finishedAt: DateTime.utc(2026, 10, 13, 11, 49, 50),
    ),
  ],
);
