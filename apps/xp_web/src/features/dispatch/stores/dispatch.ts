import { defineStore } from 'pinia'
import { computed, onScopeDispose, ref } from 'vue'

import {
  api,
  ApiFailure,
  dataOf,
  failureMessage,
  type DispatchPlan,
  type DispatchRequest,
  type Project,
  type Release,
  type Run,
  type VersionBump,
  type Workflow,
  type WorkflowSchema,
  type WorkflowSummary,
} from '@/api/client'

/** How long typing pauses before the preview is worked out again. */
export const typingPause = 400

/** The states of a release that reached a store: a patch or a new build can name it. */
const reachedAStore = new Set<Release['state']>(['uploaded', 'in_review', 'approved', 'live', 'merged'])

/** [release] as a release input takes it: `x.y.z+build`. */
export function releaseValue(release: Pick<Release, 'version' | 'build'>): string {
  return `${release.version}+${release.build}`
}

/** Whether the form leaves [workflow] out: an archived one, and the merge of a release, which starts from the release. */
function hidden(workflow: WorkflowSummary): boolean {
  return workflow.archivedAt !== undefined || (workflow.builtin && workflow.name === 'release-merge')
}

function toggle(values: string[], value: string): string[] {
  return values.includes(value) ? values.filter((each) => each !== value) : [...values, value]
}

/**
 * The Dispatch form, as the Mac app's sheet: picks a workflow and what to
 * run it for, its inputs (the last dispatch's to begin with), previews
 * where each job lands and which gates it hits (`dryRun=true`), and
 * dispatches.
 */
export const useDispatchStore = defineStore('dispatch', () => {
  const project = ref<Project | null>(null)
  const loading = ref(true)
  const workflows = ref<WorkflowSummary[]>([])
  const workflow = ref<Workflow | null>(null)
  const schema = ref<WorkflowSchema | null>(null)
  /** The path of the app to run for. */
  const app = ref('.')
  /** The flavors picked, or `null` for the ones the engine takes by default. */
  const flavors = ref<string[] | null>(null)
  /** The platforms picked, or `null` for every platform the app has. */
  const platforms = ref<string[] | null>(null)
  const gitRef = ref('')
  const bump = ref<VersionBump>('keep')
  /** The version `x.y.z` typed instead of a bump; empty for the bump. */
  const version = ref('')
  /** The values set for the workflow's inputs; one not here takes its default. */
  const inputs = ref<Record<string, unknown>>({})
  /** The JSON inputs whose text does not parse. */
  const invalidInputs = ref<string[]>([])
  /** The releases of the project that reached a store, newest first, for a release input. */
  const releases = ref<Release[] | null>(null)
  const preview = ref<DispatchPlan | null>(null)
  const previewing = ref(false)
  /** That the engine does not have the ref yet: the dispatch fetches it first. */
  const refNotice = ref<string | null>(null)
  const submitting = ref(false)
  const error = ref<string | null>(null)

  let generation = 0
  let timer: ReturnType<typeof setTimeout> | undefined

  const chosenFlavors = computed(() => flavors.value ?? preview.value?.flavors ?? [])
  const chosenPlatforms = computed(() => platforms.value ?? preview.value?.platforms ?? [])

  /** The app the run is for. */
  const chosenApp = computed(
    () => project.value?.profile.apps.find((each) => each.path === app.value) ?? null,
  )

  /** Whether the workflow writes a version, so the bump matters. */
  const bumps = computed(() => preview.value?.version !== undefined)

  /** The release input of the workflow, if it has one. */
  const releaseInput = computed(
    () => workflow.value?.inputs?.find((input) => input.type === 'release') ?? null,
  )

  /** Whether the workflow takes a release and the project has none yet. */
  const noReleases = computed(
    () => releaseInput.value !== null && releases.value !== null && releases.value.length === 0,
  )

  const jobCount = computed(
    () => preview.value?.stages.reduce((count, stage) => count + stage.jobs.length, 0) ?? 0,
  )

  /** Every gate the run would stop at for an approval. */
  const gates = computed(() => [...new Set(preview.value?.stages.flatMap((stage) => stage.gates))])

  const blocked = computed(() => preview.value?.skipped.some((job) => job.blocks) ?? false)

  /** What people call [gate]: the schema's label, else the gate itself. */
  function gateLabel(gate: string): string {
    return schema.value?.gateLabels[gate] ?? gate
  }

  /**
   * The values the dispatch sends: those of declared inputs that are set,
   * and the first option of a choice without a default, which the form
   * shows as chosen.
   */
  const givenInputs = computed(() => {
    const given: Record<string, unknown> = {}
    for (const input of workflow.value?.inputs ?? []) {
      const value =
        inputs.value[input.name] ??
        (input.type === 'choice' && input.default === undefined ? input.options?.[0] : undefined)
      if (value !== undefined) given[input.name] = value
    }
    return given
  })

  /** The body of the dispatch. */
  const request = computed<DispatchRequest>(() => {
    const typed = version.value.trim()
    const release = releaseInput.value
    const releaseVersion = release ? inputs.value[release.name] : undefined
    const body: DispatchRequest = {
      app: app.value,
      inputs: givenInputs.value as DispatchRequest['inputs'],
    }
    if (gitRef.value.trim() !== '') body.ref = gitRef.value.trim()
    if (flavors.value) body.flavors = flavors.value
    if (platforms.value) body.platforms = platforms.value as DispatchRequest['platforms']
    if (bumps.value && typed === '') body.bump = bump.value
    if (bumps.value && typed !== '') body.version = typed
    if (typeof releaseVersion === 'string') body.releaseVersion = releaseVersion
    return body
  })

  /** Whether the form can dispatch now. */
  const canDispatch = computed(
    () =>
      !loading.value &&
      !submitting.value &&
      !previewing.value &&
      workflow.value !== null &&
      invalidInputs.value.length === 0 &&
      !noReleases.value &&
      (refNotice.value !== null || (!blocked.value && jobCount.value > 0)),
  )

  /** Works the preview out again: at once, or after typing pauses. */
  function changed(typed = false) {
    previewing.value = true
    clearTimeout(timer)
    const asked = ++generation
    timer = setTimeout(() => void plan(asked), typed ? typingPause : 0)
  }

  async function plan(asked: number) {
    const current = workflow.value
    const owner = project.value
    if (!current || !owner) {
      previewing.value = false
      return
    }
    try {
      const planned = await dataOf(
        api.POST('/projects/{id}/workflows/{workflowId}/dispatch', {
          params: { path: { id: owner.id, workflowId: current.id }, query: { dryRun: true } },
          body: request.value,
        }),
      )
      if (asked !== generation) return
      preview.value = planned as DispatchPlan
      refNotice.value = null
      error.value = null
    } catch (failure) {
      if (asked !== generation) return
      const unknownRef = failure instanceof ApiFailure && failure.reason === 'ref_unknown'
      preview.value = null
      refNotice.value = unknownRef ? failure.message : null
      error.value = unknownRef ? null : failureMessage(failure)
    } finally {
      if (asked === generation) previewing.value = false
    }
  }

  /** The request of the newest run of [workflowId] (any workflow when absent), if any. */
  async function lastRequest(projectId: string, workflowId?: string) {
    try {
      const page = await dataOf(
        api.GET('/runs', {
          params: { query: { project: projectId, workflow: workflowId, limit: 1 } },
        }),
      )
      return page.runs[0]
    } catch {
      return undefined
    }
  }

  async function loadReleases(projectId: string, inputName: string) {
    const answer = await dataOf(
      api.GET('/releases', { params: { query: { project: projectId } } }),
    )
    releases.value = answer.releases
      .filter((release) => reachedAStore.has(release.state))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    const newest = releases.value[0]
    if (inputs.value[inputName] === undefined && newest) {
      inputs.value = { ...inputs.value, [inputName]: releaseValue(newest) }
    }
  }

  /**
   * Opens the form for [owner], on [workflowId] (an id or a name such as
   * `prod-release`), else the workflow dispatched last, else the first.
   */
  async function start(owner: Project, workflowId?: string): Promise<void> {
    generation++
    clearTimeout(timer)
    project.value = owner
    app.value = owner.profile.apps[0]?.path ?? '.'
    gitRef.value = owner.defaultBaseBranch
    loading.value = true
    workflows.value = []
    workflow.value = null
    preview.value = null
    refNotice.value = null
    error.value = null
    submitting.value = false
    try {
      const [listed, described] = await Promise.all([
        dataOf(api.GET('/projects/{id}/workflows', { params: { path: { id: owner.id } } })),
        schema.value ? Promise.resolve(schema.value) : dataOf(api.GET('/workflows/schema')),
      ])
      schema.value = described
      workflows.value = listed.workflows.filter((each) => !hidden(each))
      const wanted = workflowId ?? (await lastRequest(owner.id))?.workflowId
      const first =
        workflows.value.find((each) => each.id === wanted) ??
        workflows.value.find((each) => each.name === wanted) ??
        workflows.value[0]
      if (first) await choose(first.id)
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loading.value = false
    }
  }

  /** Picks the workflow [workflowId], with the inputs of its last dispatch. */
  async function choose(workflowId: string): Promise<void> {
    const owner = project.value
    if (!owner) return
    const asked = ++generation
    clearTimeout(timer)
    previewing.value = true
    preview.value = null
    refNotice.value = null
    error.value = null
    try {
      const [found, last] = await Promise.all([
        dataOf(
          api.GET('/projects/{id}/workflows/{workflowId}', {
            params: { path: { id: owner.id, workflowId } },
          }),
        ),
        lastRequest(owner.id, workflowId),
      ])
      if (asked !== generation) return
      workflow.value = found
      flavors.value = null
      platforms.value = null
      inputs.value = { ...(last?.request?.inputs ?? {}) }
      invalidInputs.value = []
      releases.value = null
      if (releaseInput.value) await loadReleases(owner.id, releaseInput.value.name)
      if (asked === generation) changed()
    } catch (failure) {
      if (asked !== generation) return
      previewing.value = false
      error.value = failureMessage(failure)
    }
  }

  function chooseApp(path: string) {
    app.value = path
    flavors.value = null
    platforms.value = null
    changed()
  }

  function toggleFlavor(flavor: string) {
    flavors.value = toggle(chosenFlavors.value, flavor)
    changed()
  }

  function togglePlatform(platform: string) {
    platforms.value = toggle(chosenPlatforms.value, platform)
    changed()
  }

  function setRef(value: string) {
    gitRef.value = value
    changed(true)
  }

  function setBump(value: VersionBump) {
    bump.value = value
    changed()
  }

  function setVersion(value: string) {
    version.value = value
    changed(true)
  }

  /**
   * Sets the input [name] to [value]; [valid] is false while the text of a
   * JSON input does not parse. Typed values wait for the typing to pause.
   */
  function setInput(name: string, value: unknown, { valid = true, typed = false } = {}) {
    inputs.value = { ...inputs.value, [name]: value }
    invalidInputs.value = valid
      ? invalidInputs.value.filter((each) => each !== name)
      : [...new Set([...invalidInputs.value, name])]
    changed(typed)
  }

  /**
   * Stops the preview that waits for typing to pause, and drops an answer
   * still on its way: the form closed.
   */
  function stop() {
    generation++
    clearTimeout(timer)
    previewing.value = false
  }
  onScopeDispose(stop)

  /** Dispatches the run the form previews. The run, or `null` with [error] saying why not. */
  async function submit(): Promise<Run | null> {
    const owner = project.value
    const current = workflow.value
    if (!canDispatch.value || !owner || !current) return null
    submitting.value = true
    error.value = null
    try {
      return (await dataOf(
        api.POST('/projects/{id}/workflows/{workflowId}/dispatch', {
          params: { path: { id: owner.id, workflowId: current.id } },
          body: request.value,
        }),
      )) as Run
    } catch (failure) {
      error.value = failureMessage(failure)
      return null
    } finally {
      submitting.value = false
    }
  }

  return {
    project,
    loading,
    workflows,
    workflow,
    app,
    flavors,
    platforms,
    gitRef,
    bump,
    version,
    inputs,
    invalidInputs,
    releases,
    preview,
    previewing,
    refNotice,
    submitting,
    error,
    chosenApp,
    chosenFlavors,
    chosenPlatforms,
    bumps,
    releaseInput,
    noReleases,
    jobCount,
    gates,
    blocked,
    request,
    canDispatch,
    gateLabel,
    start,
    choose,
    chooseApp,
    toggleFlavor,
    togglePlatform,
    setRef,
    setBump,
    setVersion,
    setInput,
    submit,
    stop,
  }
})
