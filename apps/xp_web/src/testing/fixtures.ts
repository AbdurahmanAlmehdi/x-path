import type {
  Approval,
  Credential,
  DispatchPlan,
  Job,
  NamedCredential,
  Person,
  Project,
  Release,
  Run,
  Runner,
  StorageReport,
  TestBaseline,
  TestRunResponse,
  TokenInfo,
  Workflow,
  WorkflowSummary,
} from '@/api/client'

/** A project with one app of the flavors dev and prod, for Android and iOS. */
export function projectOf(overrides: Partial<Project> = {}): Project {
  return {
    id: 'prj_1',
    host: 'github.com',
    sourceKey: '1',
    fullName: 'acme/app',
    remote: 'https://github.com/acme/app.git',
    defaultBaseBranch: 'main',
    findings: [],
    profile: {
      layout: 'single',
      branches: {},
      workflows: [],
      apps: [
        {
          name: 'app',
          path: '.',
          framework: 'flutter',
          version: '1.2.0+7',
          storeCountry: 'us',
          flutterVersion: '3.47.0',
          hasIos: true,
          hasAndroid: true,
          iosPackageManager: 'none',
          iosLinux: true,
          plists: [],
          flavors: [
            { name: 'dev', implicit: false, entrypoint: 'lib/main_dev.dart', shorebird: false, prod: false, versionFiles: [], sources: [], androidAppId: 'com.acme.dev' },
            { name: 'prod', implicit: false, entrypoint: 'lib/main_prod.dart', shorebird: false, prod: true, versionFiles: [], sources: [], iosBundleId: 'com.acme' },
          ],
        },
      ],
    },
    ...overrides,
  } as unknown as Project
}

/** A run of the workflow `wf_1`, with one job per stage. */
export function runOf(overrides: Partial<Run> = {}): Run {
  return {
    id: 'run_1',
    projectId: 'prj_1',
    workflowId: 'wf_1',
    workflowVersionId: 'wfv_1',
    sha: '0123456789abcdef0123456789abcdef01234567',
    ref: 'main',
    state: 'running',
    locksProject: false,
    version: '1.2.0',
    build: 8,
    createdAt: '2026-11-14T09:00:00Z',
    jobs: [
      { id: 'job_1', name: 'Check dev for android', stage: 0, state: 'succeeded' },
      { id: 'job_2', name: 'Build dev for android', stage: 1, state: 'running' },
    ],
    request: { flavors: ['dev'], platforms: ['android'], inputs: {} },
    origin: { kind: 'person', personId: 'per_1', personName: 'Sam', tokenId: 'tok_1' },
    ...overrides,
  }
}

/** A job of `run_1` with two steps. */
export function jobOf(overrides: Partial<Job> = {}): Job {
  return {
    id: 'job_2',
    projectId: 'prj_1',
    workflowVersionId: 'wfv_1',
    runId: 'run_1',
    name: 'Build dev for android',
    state: 'running',
    createdAt: '2026-11-14T09:00:00Z',
    steps: [
      { ordinal: 0, kind: 'git.checkout', state: 'succeeded', sideEffect: false, attempts: 1, startedAt: '2026-11-14T09:00:00Z', finishedAt: '2026-11-14T09:00:02Z' },
      { ordinal: 1, kind: 'build.android', state: 'running', sideEffect: false, attempts: 1, startedAt: '2026-11-14T09:00:02Z' },
    ],
    ...overrides,
  }
}

/** A workflow of `prj_1` as the list has it. */
export function workflowSummaryOf(overrides: Partial<WorkflowSummary> = {}): WorkflowSummary {
  return {
    id: 'wf_1',
    projectId: 'prj_1',
    name: 'dev-build',
    title: 'Dev build',
    builtin: true,
    version: { id: 'wfv_1', version: 1, createdAt: '2026-11-14T09:00:00Z' },
    ...overrides,
  }
}

/** A workflow of `prj_1` in full. */
export function workflowOf(overrides: Partial<Workflow> = {}): Workflow {
  const version = { id: 'wfv_1', version: 1, createdAt: '2026-11-14T09:00:00Z' }
  return {
    id: 'wf_1',
    projectId: 'prj_1',
    name: 'dev-build',
    builtin: true,
    version,
    versions: [version],
    yaml: 'schema: 1\n',
    inputs: [],
    ...overrides,
  }
}

/** The plan of a dispatch: one stage of one job on the engine. */
export function planOf(overrides: Partial<DispatchPlan> = {}): DispatchPlan {
  return {
    flavors: ['dev'],
    platforms: ['android', 'ios'],
    stages: [
      {
        name: 'build',
        gates: [],
        jobs: [{ name: 'Build dev for android', capabilities: ['android'], engineOnly: false, local: true }],
      },
    ],
    skipped: [],
    ...overrides,
  }
}

/** A release of `prj_1`, live on both stores, read through their APIs. */
export function releaseOf(overrides: Partial<Release> = {}): Release {
  return {
    id: 'rel_1',
    projectId: 'prj_1',
    app: '.',
    flavor: 'prod',
    version: '1.1.0',
    build: 6,
    state: 'live',
    stores: [
      { store: 'apple', state: 'live', source: 'api', changedAt: '2026-11-12T09:00:00Z' },
      { store: 'play', state: 'live', source: 'api', changedAt: '2026-11-12T10:00:00Z' },
    ],
    builds: [{ build: 6, runId: 'run_1', createdAt: '2026-11-10T09:05:00Z' }],
    mergeEnabled: false,
    branch: 'release/1.1.0',
    baseBranch: 'main',
    tag: 'v1.1.0+6',
    headSha: 'abcdef0123456789abcdef0123456789abcdef01',
    createdAt: '2026-11-10T09:00:00Z',
    updatedAt: '2026-11-12T10:00:00Z',
    ...overrides,
  }
}

/** An approval of `prod_release` that job_2 of run_1 waits for. */
export function approvalOf(overrides: Partial<Approval> = {}): Approval {
  return {
    id: 'apr_1',
    projectId: 'prj_1',
    action: 'prod_release',
    sha: '0123456789abcdef0123456789abcdef01234567',
    version: '1.2.0+8',
    runId: 'run_1',
    jobId: 'job_2',
    state: 'pending',
    createdAt: '2026-11-14T09:00:00Z',
    expiresAt: '2026-11-15T09:00:00Z',
    ...overrides,
  }
}

/** The test run of job_2 on main: one new failure, one fixed, compared with job_1's baseline. */
export function testRunOf(overrides: Partial<TestRunResponse['run']> = {}): TestRunResponse {
  return {
    run: {
      id: 'tr_2',
      jobId: 'job_2',
      branch: 'main',
      appPath: '.',
      baseline: false,
      createdAt: '2026-11-14T09:00:00Z',
      counts: { total: 10, passed: 7, failed: 2, errored: 0, skipped: 1 },
      diff: {
        comparedTo: 'job_1',
        newFailures: [{ suite: 'test/a_test.dart', name: 'a breaks' }],
        fixed: [{ suite: 'test/c_test.dart', name: 'c works' }],
        missing: [],
        stillFailing: 1,
      },
      ...overrides,
    },
    total: 2,
    offset: 0,
    tests: [
      { suite: 'test/a_test.dart', name: 'a breaks', status: 'failed', message: 'Expected: 1' },
      { suite: 'test/b_test.dart', name: 'b still breaks', status: 'errored' },
    ],
  }
}

/** The baseline of main, from job_1. */
export function baselineOf(overrides: Partial<TestBaseline> = {}): TestBaseline {
  return {
    appPath: '.',
    branch: 'main',
    jobId: 'job_1',
    createdAt: '2026-11-13T09:00:00Z',
    counts: { total: 10, passed: 8, failed: 1, errored: 0, skipped: 1 },
    ...overrides,
  }
}

/** A runner online and idle, probed for Android and Flutter. */
export function runnerOf(overrides: Partial<Runner> = {}): Runner {
  return {
    id: 'rnr_1',
    name: 'mac-mini',
    status: 'online',
    capabilities: ['android', 'flutter'],
    slots: 2,
    jobIds: [],
    os: 'macos',
    arch: 'arm64',
    version: '1.4.0',
    cores: 10,
    lastHeartbeat: '2026-11-14T09:00:00Z',
    createdAt: '2026-11-10T09:00:00Z',
    ...overrides,
  }
}

/** A person of the engine. */
export function personOf(overrides: Partial<Person> = {}): Person {
  return {
    id: 'per_0123456789abcdef',
    name: 'Sam',
    role: 'admin',
    createdAt: '2026-11-14T09:00:00Z',
    ...overrides,
  }
}

/** A token of Sam's. */
export function tokenOf(overrides: Partial<TokenInfo> = {}): TokenInfo {
  return {
    id: 'tok_2',
    name: 'xp on my laptop',
    kind: 'cli',
    createdAt: '2026-11-14T09:00:00Z',
    personId: 'per_0123456789abcdef',
    ...overrides,
  }
}

/** A named keystore, verified, used by the dev flavor of prj_1. */
export function namedCredentialOf(overrides: Partial<NamedCredential> = {}): NamedCredential {
  return {
    id: 'crd_1',
    name: 'Upload keystore',
    kind: 'keystore',
    status: 'verified',
    account: 'upload',
    usedBy: [{ projectId: 'prj_1', project: 'acme/app', app: '.', flavor: 'dev', status: 'verified' }],
    ...overrides,
  }
}

/** The keystore the dev flavor of prj_1 uses. */
export function flavorCredentialOf(overrides: Partial<Credential> = {}): Credential {
  return {
    id: 'crd_1',
    name: 'Upload keystore',
    projectId: 'prj_1',
    app: '.',
    flavor: 'dev',
    kind: 'keystore',
    status: 'verified',
    ...overrides,
  }
}

/** What the engine keeps: artifacts and logs, some of it reclaimable. */
export function storageReportOf(overrides: Partial<StorageReport> = {}): StorageReport {
  return {
    generatedAt: '2026-11-14T09:00:00Z',
    categories: [
      { category: 'artifacts', usedBytes: 2_000_000_000, reclaimableBytes: 1_500_000_000, items: 12 },
      { category: 'logs', usedBytes: 50_000_000, reclaimableBytes: 0, items: 40 },
    ],
    flavors: [
      {
        projectId: 'prj_1',
        app: '.',
        flavor: 'dev',
        builds: 7,
        artifacts: 14,
        usedBytes: 2_000_000_000,
        reclaimableBytes: 1_500_000_000,
      },
    ],
    retention: { keepPerFlavor: 5, logDays: 90 },
    ...overrides,
  }
}
