import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  dataOf,
  failureMessage,
  type Job,
  type TestBaseline,
  type TestRun,
  type TestRunResponse,
} from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'

/** A test run the app knows of, by the job that ran it, with what is known of it before it is read. */
export interface KnownTestRun {
  jobId: string
  branch?: string
  appPath?: string
  createdAt?: string
  /** Whether it is a baseline of its app and branch. */
  baseline: boolean
}

/**
 * The tests of a project: a run against its baseline, new failures first
 * (D-21). The engine lists no past runs, so the runs on offer are the
 * baselines, the runs that end while the page is open and the run a job
 * page opened.
 */
export const useTestsStore = defineStore('tests', () => {
  const projectId = ref<string | null>(null)
  /** The baselines of the project, one per app and branch. */
  const baselines = ref<TestBaseline[]>([])
  const loaded = ref(false)
  /** Why the baselines could not be read. */
  const error = ref<string | null>(null)
  /** The runs of the project that ended while the page was open, newest first. */
  const completed = ref<KnownTestRun[]>([])
  /** The run picked, if any. */
  const selectedJobId = ref<string | null>(null)
  /** The run shown, with its failing tests. */
  const run = ref<TestRunResponse | null>(null)
  /** Every run read so far, by job. */
  const read = ref<Record<string, TestRun>>({})
  /** Why the run shown could not be read. */
  const runError = ref<string | null>(null)
  /** The job that ran it: its test step's duration. */
  const job = ref<Job | null>(null)
  /** The job whose run was read last. */
  let reading: string | null = null

  const newestBaseline = computed(() =>
    [...baselines.value].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0],
  )

  /** The job of the run shown: the one picked, else the latest that ended, else the newest baseline. */
  const shownJobId = computed(
    () => selectedJobId.value ?? completed.value[0]?.jobId ?? newestBaseline.value?.jobId ?? null,
  )

  /** The baseline the run shown was compared with, if the project still has it. */
  const comparedBaseline = computed(() =>
    baselines.value.find((baseline) => baseline.jobId === run.value?.run.diff.comparedTo),
  )

  /** Every run the page knows of: those that ended, the one picked, those read, then the baselines, newest first. */
  const runs = computed<KnownTestRun[]>(() => {
    const known = new Map<string, KnownTestRun>()
    function add(entry: KnownTestRun) {
      if (known.has(entry.jobId)) return
      const seen = read.value[entry.jobId]
      known.set(
        entry.jobId,
        seen
          ? {
              jobId: seen.jobId,
              branch: seen.branch,
              appPath: seen.appPath,
              createdAt: seen.createdAt,
              baseline: seen.baseline,
            }
          : entry,
      )
    }
    completed.value.forEach(add)
    if (selectedJobId.value) add({ jobId: selectedJobId.value, baseline: false })
    Object.keys(read.value).forEach((jobId) => add({ jobId, baseline: false }))
    ;[...baselines.value]
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))
      .forEach((baseline) => add({ ...baseline, baseline: true }))
    return [...known.values()]
  })

  /** How long the job's `test` step ran, in milliseconds, once it ended. */
  const duration = computed(() => {
    const step = job.value?.steps.filter((each) => each.kind === 'test').at(-1)
    if (!step?.startedAt || !step.finishedAt) return null
    return Date.parse(step.finishedAt) - Date.parse(step.startedAt)
  })

  async function loadRun(jobId: string) {
    const path = { params: { path: { id: jobId } } }
    try {
      const response = await dataOf(api.GET('/jobs/{id}/tests', path))
      if (shownJobId.value !== jobId) return
      run.value = response
      read.value = { ...read.value, [jobId]: response.run }
      runError.value = null
    } catch (failure) {
      if (shownJobId.value === jobId) runError.value = failureMessage(failure)
    }
    try {
      const ran = await dataOf(api.GET('/jobs/{id}', path))
      if (shownJobId.value === jobId) job.value = ran
    } catch {
      // The run says what matters; without its job only the duration is missing.
    }
  }

  /** Reads the run shown when it changed, or again when [again]. */
  async function show(again = false) {
    const jobId = shownJobId.value
    if (!jobId || (jobId === reading && !again)) return
    if (jobId !== reading) {
      run.value = null
      runError.value = null
      job.value = null
    }
    reading = jobId
    await loadRun(jobId)
  }

  async function loadBaselines(project: string) {
    try {
      const read = await dataOf(
        api.GET('/projects/{id}/tests/baseline', { params: { path: { id: project } } }),
      )
      if (projectId.value !== project) return
      baselines.value = read.baselines
      error.value = null
    } catch (failure) {
      if (projectId.value === project) error.value = failureMessage(failure)
    } finally {
      if (projectId.value === project) loaded.value = true
    }
  }

  /** Shows the tests of [project], with the run of [jobId] if given, else the latest. */
  async function open(project: string, jobId: string | null = null): Promise<void> {
    if (projectId.value !== project) {
      projectId.value = project
      baselines.value = []
      completed.value = []
      read.value = {}
      loaded.value = false
      error.value = null
      reading = null
    }
    selectedJobId.value = jobId
    await Promise.all([show(), loadBaselines(project).then(() => show())])
  }

  /** Shows the run of [jobId]. */
  function select(jobId: string) {
    selectedJobId.value = jobId
    void show()
  }

  /** Follows the test runs of the project that end. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      const project = projectId.value
      if (!project) return
      if (item.kind === 'resync') {
        void loadBaselines(project).then(() => show(true))
        return
      }
      const { event } = item
      if (event.type !== 'test_run.completed' || payloadValue(event, 'projectId') !== project) return
      const jobId = payloadValue(event, 'jobId')
      if (!jobId) return
      const baseline = (event.payload as { baseline?: unknown }).baseline === true
      completed.value = [
        { jobId, branch: payloadValue(event, 'branch'), baseline },
        ...completed.value.filter((each) => each.jobId !== jobId),
      ]
      void (baseline ? loadBaselines(project) : Promise.resolve()).then(() =>
        show(jobId === shownJobId.value),
      )
    })
  }

  return {
    projectId,
    baselines,
    loaded,
    error,
    completed,
    selectedJobId,
    run,
    read,
    runError,
    job,
    shownJobId,
    comparedBaseline,
    runs,
    duration,
    open,
    select,
    follow,
  }
})
