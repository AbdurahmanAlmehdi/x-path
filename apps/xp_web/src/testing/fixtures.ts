import type {
  DispatchPlan,
  Job,
  Project,
  Release,
  Run,
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

/** A release of `prj_1` in [state]. */
export function releaseOf(overrides: Partial<Release> = {}): Release {
  return {
    id: 'rel_1',
    projectId: 'prj_1',
    app: '.',
    flavor: 'prod',
    version: '1.1.0',
    build: 6,
    state: 'live',
    createdAt: '2026-11-10T09:00:00Z',
    ...overrides,
  } as unknown as Release
}
