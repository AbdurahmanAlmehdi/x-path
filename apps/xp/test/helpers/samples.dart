import 'package:xp_api/xp_api.dart';

final at = DateTime.utc(2026, 10, 14, 9, 30);

final project = Project(
  id: 'prj_1',
  host: 'github.com',
  sourceKey: '7',
  githubRepoId: 7,
  fullName: 'acme/app',
  remote: 'https://github.com/acme/app.git',
  defaultBaseBranch: 'main',
  scannedAt: at,
  profile: const ProjectProfile(
    apps: [
      AppProfile(
        name: 'app',
        path: '.',
        version: '1.2.3+4',
        hasIos: true,
        hasAndroid: true,
        flavors: [
          FlavorProfile(
            name: 'prod',
            entrypoint: 'lib/main.dart',
            prod: true,
            androidAppId: 'com.acme.app',
            iosBundleId: 'com.acme.app',
          ),
          FlavorProfile(name: 'dev', entrypoint: 'lib/main_dev.dart'),
        ],
      ),
    ],
  ),
  findings: const [
    Finding(
      severity: FindingSeverity.warning,
      code: 'x',
      message: 'Something is off',
      fix: 'Fix it',
    ),
  ],
);

const bareProject = Project(
  id: 'prj_2',
  host: 'github.com',
  sourceKey: '8',
  githubRepoId: 8,
  fullName: 'acme/other',
  remote: 'https://github.com/acme/other.git',
  defaultBaseBranch: 'main',
);

final workflowVersion = WorkflowVersionInfo(
  id: 'wfv_1',
  version: 2,
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
  builtin: true,
  version: workflowVersion,
);

Run run({
  RunState state = RunState.running,
  String id = 'run_1',
  String? version,
  int? build,
  DispatchRequest? request,
}) => Run(
  id: id,
  projectId: 'prj_1',
  workflowId: 'wf_1',
  workflowVersionId: 'wfv_1',
  sha: 'a' * 40,
  state: state,
  locksProject: true,
  version: version,
  build: build,
  request: request,
  createdAt: at,
  jobs: const [
    RunJob(id: 'job_1', name: 'prepare', stage: 0, state: JobState.running),
  ],
);

Job job({JobState state = JobState.running, String? name = 'prepare'}) => Job(
  id: 'job_1',
  projectId: 'prj_1',
  workflowVersionId: 'wfv_1',
  state: state,
  name: name,
  message: state == JobState.failed ? 'It broke' : null,
  createdAt: at,
  startedAt: at,
  steps: const [
    JobStep(
      ordinal: 0,
      kind: 'guard',
      state: StepState.succeeded,
      sideEffect: false,
      attempts: 1,
    ),
  ],
);

Approval approval({
  ApprovalState state = ApprovalState.pending,
  String? version = '1.2.3+4',
  String? reason,
  bool decided = false,
}) => Approval(
  id: 'apr_1',
  projectId: 'prj_1',
  action: 'prod_release',
  sha: 'a' * 40,
  version: version,
  runId: 'run_1',
  state: state,
  createdAt: at,
  expiresAt: at.add(const Duration(hours: 24)),
  reason: reason,
  decidedAt: decided ? at : null,
  decidedBy: decided
      ? const DecidedBy(
          tokenId: 'tok_1',
          name: 'My Mac',
          kind: DeviceTokenKind.app,
        )
      : null,
);

Release release({String? prUrl = 'https://github.com/acme/app/pull/9'}) =>
    Release(
      id: 'rel_1',
      projectId: 'prj_1',
      app: '.',
      flavor: 'prod',
      version: '1.2.3',
      build: 45,
      state: ReleaseState.inReview,
      stores: [
        StoreStatus(
          store: ReleaseStore.apple,
          state: StoreState.inReview,
          source: StatusSource.api,
          checkedAt: at,
        ),
      ],
      builds: const [],
      mergeEnabled: false,
      branch: 'release/1.2.3',
      tag: 'v1.2.3+45',
      prUrl: prUrl,
      message: 'Waiting',
      createdAt: at,
      updatedAt: at,
    );

Artifact artifact({int size = 3}) => Artifact(
  id: 'art_1',
  jobId: 'job_1',
  kind: ArtifactKind.apk,
  name: 'app.apk',
  size: size,
  sha256: 'b' * 64,
  pinned: true,
  createdAt: at,
);

StorageReport storageReport() => StorageReport(
  generatedAt: at,
  categories: const [
    CategoryUsage(
      category: StorageCategory.artifacts,
      usedBytes: 3 * 1024 * 1024,
      reclaimableBytes: 1024,
      items: 2,
    ),
  ],
  flavors: const [],
  retention: const RetentionSettings(),
);

final runner = Runner(
  id: 'rnr_1',
  name: 'mac-mini',
  status: RunnerStatus.revoked,
  capabilities: const ['flutter'],
  slots: 1,
  jobIds: const [],
  createdAt: DateTime.utc(2026, 10, 14, 9),
  revokedAt: DateTime.utc(2026, 10, 14, 10),
);

final ascCredential = NamedCredential(
  id: 'crd_1',
  name: 'Acme ASC',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
  account: 'KEY123',
  checkedAt: at,
  usedBy: const [
    CredentialUsage(
      projectId: 'prj_1',
      project: 'acme/app',
      app: '.',
      flavor: 'prod',
      status: CredentialStatus.verified,
    ),
    CredentialUsage(
      projectId: 'prj_2',
      app: '.',
      flavor: 'default',
      status: CredentialStatus.rejected,
      message: 'The key cannot see com.acme.other.',
      fix: 'Give the key access to the app.',
    ),
  ],
);

const slackCredential = NamedCredential(
  id: 'crd_2',
  name: 'Team Slack',
  kind: CredentialKind.slack,
  status: CredentialStatus.rejected,
  message: 'Slack answered 404.',
  fix: 'Make a new webhook.',
);

/// The credential the flavor [flavor] of `prj_1` uses.
Credential assigned(
  String flavor, {
  String id = 'crd_1',
  String? name = 'Acme ASC',
  CredentialKind kind = CredentialKind.ascKey,
  CredentialStatus status = CredentialStatus.verified,
  String? message,
  String? fix,
}) => Credential(
  id: id,
  name: name,
  projectId: 'prj_1',
  app: '.',
  flavor: flavor,
  kind: kind,
  status: status,
  message: message,
  fix: fix,
);
