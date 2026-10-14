import 'package:xp_api/xp_api.dart';

final at = DateTime.utc(2026, 10, 14, 9);

const project = Project(
  id: 'prj_1',
  githubRepoId: 7,
  fullName: 'acme/app',
  remote: 'https://github.com/acme/app.git',
  defaultBaseBranch: 'main',
);

final job = Job(
  id: 'job_1',
  projectId: 'prj_1',
  workflowVersionId: 'wfv_1',
  state: JobState.running,
  createdAt: at,
  steps: const [],
);

final run = Run(
  id: 'run_1',
  projectId: 'prj_1',
  workflowId: 'wf_1',
  workflowVersionId: 'wfv_1',
  sha: 'a' * 40,
  state: RunState.waitingForApproval,
  locksProject: true,
  createdAt: at,
  jobs: const [],
);

final artifact = Artifact(
  id: 'art_1',
  jobId: 'job_1',
  kind: ArtifactKind.apk,
  name: 'app.apk',
  size: 3,
  sha256: 'b' * 64,
  pinned: false,
  createdAt: at,
);

const credential = Credential(
  id: 'crd_1',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.playSa,
  status: CredentialStatus.verified,
);

final approval = Approval(
  id: 'apr_1',
  projectId: 'prj_1',
  action: 'prod_release',
  sha: 'a' * 40,
  state: ApprovalState.pending,
  createdAt: at,
  expiresAt: at.add(const Duration(hours: 24)),
);

final release = Release(
  id: 'rel_1',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  version: '1.2.3',
  build: 45,
  state: ReleaseState.inReview,
  stores: const [],
  builds: const [],
  mergeEnabled: false,
  createdAt: at,
  updatedAt: at,
);

final workflowVersion = WorkflowVersionInfo(
  id: 'wfv_1',
  version: 1,
  createdAt: at,
);

final workflow = Workflow(
  id: 'wf_1',
  projectId: 'prj_1',
  name: 'dev-build',
  builtin: false,
  version: workflowVersion,
  versions: [workflowVersion],
  yaml: 'name: dev-build\n',
);

final workflowSummary = WorkflowSummary(
  id: 'wf_1',
  projectId: 'prj_1',
  name: 'dev-build',
  builtin: false,
  version: workflowVersion,
);

const counts = TestCounts(
  total: 3,
  passed: 2,
  failed: 1,
  errored: 0,
  skipped: 0,
);

final testRunResponse = TestRunResponse(
  run: TestRun(
    id: 'tst_1',
    jobId: 'job_1',
    branch: 'main',
    appPath: '.',
    baseline: false,
    createdAt: at,
    counts: counts,
    diff: const TestRunDiff(
      newFailures: [],
      fixed: [],
      missing: [],
      stillFailing: 0,
    ),
  ),
  total: 1,
  offset: 0,
  tests: const [
    TestCase(suite: 'test/a_test.dart', name: 'a', status: TestStatus.failed),
  ],
);

final testBaseline = TestBaseline(
  appPath: '.',
  branch: 'main',
  jobId: 'job_0',
  createdAt: at,
  counts: counts,
);

const releaseNotes = ReleaseNotes(
  releaseId: 'rel_1',
  version: '1.2.3',
  build: 45,
  to: 'v1.2.3+45',
  commits: 0,
  groups: [],
  slack: 'slack',
  whatsapp: 'whatsapp',
);

final storageReport = StorageReport(
  generatedAt: at,
  categories: const [],
  flavors: const [],
  retention: const RetentionSettings(),
);

const freeSpaceResult = FreeSpaceResult(dryRun: true, categories: []);

final runner = Runner(
  id: 'rnr_1',
  name: 'mac-mini',
  status: RunnerStatus.online,
  capabilities: const ['flutter', 'ios-sign'],
  slots: 2,
  jobIds: const ['job_1'],
  createdAt: at,
);
