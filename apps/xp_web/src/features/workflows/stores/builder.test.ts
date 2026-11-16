import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { type Answer, errorBody, type SeenRequest, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { workflowOf, workflowSummaryOf } from '@/testing/fixtures'
import { eventually } from '@/testing/wait'

import { toYaml } from '../document'
import { draftTemplate, timing, useWorkflowBuilderStore } from './builder'

const ownYaml = `schema: 1
name: Nightly
stages:
  - name: build
    jobs:
      build:
        steps:
          - kind: git.checkout
`

const own = workflowOf({ id: 'wf_2', name: 'nightly', builtin: false, yaml: ownYaml })
const builtin = workflowOf({ yaml: ownYaml })
const summaries = [workflowSummaryOf(), workflowSummaryOf({ id: 'wf_2', name: 'nightly', builtin: false })]
const schema = {
  schema: 1,
  steps: [],
  gates: ['prod_release'],
  capabilities: ['flutter'],
  matrixAxes: ['platform', 'flavor'],
  platforms: ['android', 'ios'],
  gateLabels: {},
  variables: [],
}
const templates = [
  { id: 'blank', title: 'Blank', description: 'Nothing yet.', yaml: 'schema: 1\nstages: []\n' },
  { id: 'android-firebase', title: 'Android to Firebase', description: 'Builds.', yaml: ownYaml },
]

function engine(routes: Record<string, Answer | ((request: SeenRequest) => Answer | Promise<Answer>)> = {}) {
  return stubEngine({
    'GET /projects/prj_1/workflows': { status: 200, body: { workflows: summaries } },
    'GET /workflows/schema': { status: 200, body: schema },
    'GET /workflows/templates': { status: 200, body: { templates } },
    'GET /projects/prj_1/workflows/wf_1': { status: 200, body: builtin },
    'GET /projects/prj_1/workflows/wf_2': { status: 200, body: own },
    'POST /projects/prj_1/workflows/validate': { status: 200, body: { valid: true, issues: [] } },
    ...routes,
  })
}

describe('useWorkflowBuilderStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    timing.validateAfterMs = 0
  })
  afterEach(() => {
    useWorkflowBuilderStore().stop()
    timing.validateAfterMs = 400
  })

  it('opens the first workflow of the project’s own, with the schema and templates, and has the engine check it', async () => {
    const seen = engine()
    const store = useWorkflowBuilderStore()

    await store.start('prj_1')

    expect(store.loaded).toBe(true)
    expect(store.workflows).toEqual(summaries)
    expect(store.schema).toEqual(schema)
    expect(store.templates).toEqual(templates)
    expect(store.workflow?.id).toBe('wf_2')
    expect(store.name).toBe('nightly')
    expect(store.document?.stages[0]?.jobs[0]?.id).toBe('build')
    expect(store.dirty).toBe(false)
    expect(store.savesAsNew).toBe(false)
    expect(store.editable).toBe(true)
    await eventually(() => expect(store.validation).toBe('valid'))
    expect(seen.find((request) => request.path.endsWith('/validate'))?.body).toEqual({ yaml: ownYaml })
  })

  it('opens the workflow asked for, and a built-in read-only', async () => {
    engine()
    const store = useWorkflowBuilderStore()

    await store.start('prj_1', 'wf_1')

    expect(store.workflow?.id).toBe('wf_1')
    expect(store.builtin).toBe(true)
    expect(store.savesAsNew).toBe(true)
    expect(store.editable).toBe(false)
    store.setYaml('schema: 2\n')
    store.edit(draftTemplate)
    expect(store.yaml).toBe(ownYaml)
  })

  it('starts a draft when the project has no workflow, without the schema and templates the engine cannot give', async () => {
    engine({
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [] } },
      'GET /workflows/schema': { status: 500, body: errorBody('internal', 'Down.') },
      'GET /workflows/templates': { status: 500, body: errorBody('internal', 'Down.') },
    })
    const store = useWorkflowBuilderStore()

    await store.start('prj_1')

    expect(store.workflow).toBeNull()
    expect(store.schema).toBeNull()
    expect(store.templates).toEqual([])
    expect(store.yaml).toBe(toYaml(draftTemplate))
    expect(store.name).toBeNull()
    expect(store.dirty).toBe(true)
    expect(store.busy).toBeNull()
  })

  it('says why the workflows could not be read, or one could not be opened', async () => {
    engine({ 'GET /projects/prj_1/workflows': { status: 404, body: errorBody('not_found', 'No such project.') } })
    const store = useWorkflowBuilderStore()

    await store.start('prj_1')
    expect(store.loaded).toBe(true)
    expect(store.error).toBe('No such project.')

    engine()
    await store.start('prj_1')
    await store.open('wf_9')
    expect(store.error).toBe('The engine answered 404.')
    expect(store.workflow?.id).toBe('wf_2')
    expect(store.busy).toBeNull()

    await store.open('wf_1')
    expect(store.workflow?.id).toBe('wf_1')
    expect(store.error).toBeNull()
  })

  it('starts drafts from a template, the blank one without a name', async () => {
    engine()
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')

    store.draft(templates[1]!)
    expect(store.workflow).toBeNull()
    expect(store.draftName).toBe('android-firebase')
    expect(store.yaml).toBe(ownYaml)

    store.draft(templates[0]!)
    expect(store.draftName).toBeNull()
    expect(store.document?.stages).toEqual([])
  })

  it('reads typed YAML into the model, and keeps the last good reading while it cannot', async () => {
    engine()
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    store.select({ stage: 0, job: 0 })

    store.setYaml(ownYaml)
    expect(store.dirty).toBe(false)

    store.setYaml('schema: 1\nstages:\n  - name: only\n    jobs: {}\n')
    expect(store.document?.stages[0]?.name).toBe('only')
    expect(store.selection).toEqual({ stage: 0 })
    expect(store.dirty).toBe(true)

    store.setYaml('schema: 1\nstages: [\n')
    expect(store.shapeIssues[0]?.message).toMatch(/^The document is not valid YAML/)
    expect(store.document?.stages[0]?.name).toBe('only')
    expect(store.editable).toBe(false)
    store.edit(draftTemplate)
    expect(store.yaml).toBe('schema: 1\nstages: [\n')
  })

  it('writes a visual edit back as YAML and selects what it says', async () => {
    engine()
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    store.notice = 'Saved.'

    store.edit({ ...store.document!, name: 'Renamed' }, { stage: 0, job: 0 })

    expect(store.yaml).toContain('name: Renamed\n')
    expect(store.document?.name).toBe('Renamed')
    expect(store.selection).toEqual({ stage: 0, job: 0 })
    expect(store.notice).toBeNull()
    store.edit({ ...store.document!, name: 'Again' })
    expect(store.selection).toEqual({ stage: 0, job: 0 })

    store.select({ stage: 7 })
    expect(store.selection).toEqual({ stage: 0 })
  })

  it('keeps a selection as asked while there is no document', () => {
    const store = useWorkflowBuilderStore()
    store.select({ stage: 3 })
    expect(store.selection).toEqual({ stage: 3 })
  })

  it("shows the engine's issues with the model's, once each, by place", async () => {
    const issue = { line: 8, column: 19, message: 'Unknown step type "x".' }
    engine({
      'POST /projects/prj_1/workflows/validate': {
        status: 200,
        body: { valid: false, issues: [issue, { line: 1, column: 1, message: 'First.' }] },
      },
    })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    await eventually(() => expect(store.validation).toBe('invalid'))

    store.shapeIssues = [issue, { line: 8, column: 2, message: 'Earlier on the line.' }]
    expect(store.issues.map((each) => `${each.line}:${each.column}`)).toEqual(['1:1', '8:2', '8:19'])
  })

  it('says the engine is away when it cannot check, and keeps the issues it found last', async () => {
    engine()
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    await eventually(() => expect(store.validation).toBe('valid'))
    store.engineIssues = [{ line: 1, column: 1, message: 'Old.' }]

    stubUnreachableEngine()
    store.setYaml(`${ownYaml}# more\n`)

    await eventually(() => expect(store.validation).toBe('unavailable'))
    expect(store.engineIssues).toHaveLength(1)
  })

  it('drops the answer of a check the YAML changed after', async () => {
    engine()
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    await eventually(() => expect(store.validation).toBe('valid'))
    const pending: Array<(response: Response) => void> = []
    vi.stubGlobal('fetch', () => new Promise<Response>((resolve) => pending.push(resolve)))
    const answer = (body: unknown) =>
      new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } })

    store.setYaml(`${ownYaml}# one\n`)
    await eventually(() => expect(pending).toHaveLength(1))
    store.setYaml(`${ownYaml}# two\n`)
    await eventually(() => expect(pending).toHaveLength(2))
    pending[0]!(answer({ valid: false, issues: [{ line: 1, column: 1, message: 'Stale.' }] }))
    pending[1]!(answer({ valid: true, issues: [] }))

    await eventually(() => expect(store.validation).toBe('valid'))
    expect(store.engineIssues).toEqual([])
  })

  it('reveals a line each time anew', () => {
    const store = useWorkflowBuilderStore()
    store.revealIssue({ line: 3, column: 2 })
    store.revealIssue({ line: 3, column: 2 })
    expect(store.reveal).toEqual({ line: 3, column: 2, seq: 2 })
  })

  it('saves a new version of a workflow of its own', async () => {
    const saved = { ...own, yaml: `${ownYaml}# saved\n`, version: { id: 'wfv_2', version: 2, createdAt: '2026-11-14T10:00:00Z' } }
    const seen = engine({ 'PUT /projects/prj_1/workflows/wf_2': { status: 200, body: saved } })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    store.setYaml(`${ownYaml}# saved\n`)

    expect(await store.save()).toBe(true)

    expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({ yaml: `${ownYaml}# saved\n` })
    expect(store.notice).toBe('Saved nightly, version 2.')
    expect(store.dirty).toBe(false)
    expect(store.busy).toBeNull()
    expect(seen.filter((request) => request.path === '/projects/prj_1/workflows' && request.method === 'GET')).toHaveLength(2)
  })

  it('saves nothing with Save on a built-in or a draft', async () => {
    engine()
    const store = useWorkflowBuilderStore()
    await store.start('prj_1', 'wf_1')
    expect(await store.save()).toBe(false)
    store.draft()
    expect(await store.save()).toBe(false)
  })

  it("shows the issues of a refused save and reveals the first one's line", async () => {
    const issue = { line: 8, column: 19, message: 'Unknown step type "x".' }
    engine({
      'PUT /projects/prj_1/workflows/wf_2': {
        status: 422,
        body: { error: { code: 'workflow_invalid', message: 'The workflow has 1 issue.', issues: [issue] } },
      },
    })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    await eventually(() => expect(store.validation).toBe('valid'))
    store.setYaml(`${ownYaml}# changed\n`)

    expect(await store.save()).toBe(false)

    expect(store.error).toBe('The workflow has 1 issue.')
    expect(store.engineIssues).toEqual([issue])
    expect(store.validation).toBe('invalid')
    expect(store.reveal).toMatchObject({ line: 8, column: 19 })
    expect(store.dirty).toBe(true)
    expect(store.busy).toBeNull()
  })

  it('keeps the issues of a refused save over a check of the same YAML that answers later', async () => {
    const issue = { line: 8, column: 19, message: 'Unknown step type "x".' }
    let answerCheck: (answer: Answer) => void = () => {}
    let checks = 0
    engine({
      'POST /projects/prj_1/workflows/validate': () => {
        checks++
        if (checks === 1) return { status: 200, body: { valid: true, issues: [] } }
        return new Promise<Answer>((resolve) => (answerCheck = resolve))
      },
      'PUT /projects/prj_1/workflows/wf_2': {
        status: 422,
        body: { error: { code: 'workflow_invalid', message: 'The workflow has 1 issue.', issues: [issue] } },
      },
    })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    await eventually(() => expect(store.validation).toBe('valid'))
    store.setYaml(`${ownYaml}# changed\n`)
    await eventually(() => expect(checks).toBe(2))

    expect(await store.save()).toBe(false)
    answerCheck({ status: 200, body: { valid: true, issues: [] } })
    await new Promise((resolve) => setTimeout(resolve, 10))

    expect(store.engineIssues).toEqual([issue])
    expect(store.validation).toBe('invalid')
  })

  it('lets a check of YAML typed during a refused save replace its issues', async () => {
    const issue = { line: 8, column: 19, message: 'Unknown step type "x".' }
    let answerSave: (answer: Answer) => void = () => {}
    const seen = engine({
      'PUT /projects/prj_1/workflows/wf_2': () => new Promise<Answer>((resolve) => (answerSave = resolve)),
    })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    await eventually(() => expect(store.validation).toBe('valid'))
    store.setYaml(`${ownYaml}# changed\n`)
    await eventually(() => expect(store.validation).toBe('valid'))

    const saved = store.save()
    store.setYaml(`${ownYaml}# changed again\n`)
    await eventually(() => expect(seen.some((request) => request.method === 'PUT')).toBe(true))
    answerSave({
      status: 422,
      body: { error: { code: 'workflow_invalid', message: 'The workflow has 1 issue.', issues: [issue] } },
    })
    expect(await saved).toBe(false)

    await eventually(() => expect(store.validation).toBe('valid'))
    expect(store.engineIssues).toEqual([])
  })

  it('says why a save was refused without issues', async () => {
    engine({ 'PUT /projects/prj_1/workflows/wf_2': { status: 403, body: errorBody('forbidden', 'Developers only.') } })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')

    expect(await store.save()).toBe(false)
    expect(store.error).toBe('Developers only.')
    expect(store.reveal).toBeNull()
  })

  it('copies a built-in to edit, based on its version', async () => {
    const copy = workflowOf({ id: 'wf_3', name: 'dev-build-copy', builtin: false, yaml: ownYaml, basedOn: { builtin: 'dev-build', version: 1 } })
    const seen = engine({ 'POST /projects/prj_1/workflows': { status: 201, body: copy } })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1', 'wf_1')

    expect(await store.saveAs('dev-build-copy')).toBe(true)

    expect(seen.find((request) => request.method === 'POST' && !request.path.endsWith('/validate'))?.body).toEqual({
      name: 'dev-build-copy',
      yaml: ownYaml,
      basedOn: { builtin: 'dev-build', version: 1 },
    })
    expect(store.workflow?.id).toBe('wf_3')
    expect(store.builtin).toBe(false)
    expect(store.notice).toBe('Saved dev-build-copy, version 1.')
  })

  it('saves a draft under a name, and a copy of a copy keeps what it is based on', async () => {
    const based = workflowOf({ id: 'wf_3', name: 'mine', builtin: false, yaml: ownYaml, basedOn: { builtin: 'dev-build', version: 1 } })
    let created = based
    const seen = engine({ 'POST /projects/prj_1/workflows': () => ({ status: 201, body: created }) })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')
    store.draft(templates[1]!)

    expect(await store.saveAs('android')).toBe(true)
    expect(seen.at(-2)?.body).toEqual({ name: 'android', yaml: ownYaml })
    expect(store.draftName).toBeNull()

    created = { ...based, id: 'wf_4', name: 'mine-2' }
    expect(await store.saveAs('mine-2')).toBe(true)
    expect(([...seen].reverse().find((request) => request.method === 'POST' && !request.path.endsWith('/validate'))?.body as { basedOn: unknown }).basedOn).toEqual({
      builtin: 'dev-build',
      version: 1,
    })
  })

  it('keeps a save that went through when the list cannot be read again', async () => {
    let listed = 0
    engine({
      'GET /projects/prj_1/workflows': () =>
        ++listed === 1 ? { status: 200, body: { workflows: summaries } } : { status: 500, body: errorBody('internal', 'Down.') },
      'PUT /projects/prj_1/workflows/wf_2': { status: 200, body: own },
    })
    const store = useWorkflowBuilderStore()
    await store.start('prj_1')

    expect(await store.save()).toBe(true)
    expect(store.workflows).toEqual(summaries)
    expect(store.error).toBeNull()
  })

  describe('the history and the commands of a workflow of its own', () => {
    const first = { id: 'wfv_1', version: 1, createdAt: '2026-11-14T09:00:00Z' }
    const second = { id: 'wfv_2', version: 2, createdAt: '2026-11-14T10:00:00Z' }
    const oldYaml = ownYaml.replace('Nightly', 'Old')
    const twice = { ...own, version: second, versions: [first, second] }
    /** `GET .../wf_2`: version 1 when asked for, else the newest. */
    const versioned = (request: SeenRequest): Answer =>
      request.search === '?version=1'
        ? { status: 200, body: { ...twice, version: first, yaml: oldYaml } }
        : { status: 200, body: twice }

    it('compares two versions, and a newer compare replaces an older one', async () => {
      let answerLate = () => {}
      let calls = 0
      engine({
        'GET /projects/prj_1/workflows/wf_2': (request) => {
          calls++
          // One of the versions of the first compare answers last.
          if (calls === 3) return new Promise((resolve) => (answerLate = () => resolve(versioned(request))))
          return versioned(request)
        },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      const slow = store.compareVersions(1, 2)
      expect(store.versionDiff).toBeNull()
      await store.compareVersions(2, 2)
      expect(store.versionDiff).toEqual({ from: 2, to: 2, before: ownYaml, after: ownYaml })
      answerLate()
      await slow
      expect(store.versionDiff).toEqual({ from: 2, to: 2, before: ownYaml, after: ownYaml })

      await store.compareVersions(1, 2)
      expect(store.versionDiff).toEqual({ from: 1, to: 2, before: oldYaml, after: ownYaml })
      expect(store.versionError).toBeNull()
    })

    it('says why the versions could not be read, and compares nothing without a workflow', async () => {
      const seen = engine({
        'GET /projects/prj_1/workflows/wf_2': (request) =>
          request.search === '' ? { status: 200, body: twice } : { status: 404, body: errorBody('not_found', 'No such version.') },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      await store.compareVersions(1, 2)
      expect(store.versionDiff).toBeNull()
      expect(store.versionError).toBe('No such version.')

      store.draft()
      const before = seen.length
      await store.compareVersions(1, 2)
      expect(seen).toHaveLength(before)
    })

    it('saves an older version again as the newest, and opens it', async () => {
      const restored = { ...twice, version: { ...second, id: 'wfv_3', version: 3 }, versions: [first, second], yaml: oldYaml }
      const seen = engine({
        'GET /projects/prj_1/workflows/wf_2': versioned,
        'PUT /projects/prj_1/workflows/wf_2': { status: 200, body: restored },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')
      store.setYaml(`${ownYaml}# typed\n`)

      expect(await store.restoreVersion(1)).toBe(true)

      expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({ yaml: oldYaml })
      expect(store.workflow).toEqual(restored)
      expect(store.yaml).toBe(oldYaml)
      expect(store.dirty).toBe(false)
      expect(store.document?.name).toBe('Old')
      expect(store.notice).toBe('Saved version 1 again as version 3 of nightly.')
      expect(seen.filter((request) => request.path === '/projects/prj_1/workflows')).toHaveLength(2)
      expect(store.busy).toBeNull()
    })

    it('says why a version could not be saved again', async () => {
      engine({
        'GET /projects/prj_1/workflows/wf_2': versioned,
        'PUT /projects/prj_1/workflows/wf_2': {
          status: 422,
          body: { error: { code: 'workflow_invalid', message: 'The workflow has 1 issue.', issues: [] } },
        },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      expect(await store.restoreVersion(1)).toBe(false)
      expect(store.error).toBe('The workflow has 1 issue.')
      expect(store.yaml).toBe(ownYaml)
      expect(store.busy).toBeNull()
    })

    it('renames the workflow and keeps what is typed, unsaved', async () => {
      const renamed = { ...own, name: 'nightly-2' }
      const seen = engine({ 'PATCH /projects/prj_1/workflows/wf_2': { status: 200, body: renamed } })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')
      store.setYaml(`${ownYaml}# typed\n`)

      expect(await store.rename('nightly-2')).toBe(true)

      expect(seen.find((request) => request.method === 'PATCH')?.body).toEqual({ name: 'nightly-2' })
      expect(store.name).toBe('nightly-2')
      expect(store.yaml).toBe(`${ownYaml}# typed\n`)
      expect(store.dirty).toBe(true)
      expect(store.notice).toBe('Renamed to nightly-2.')
    })

    it('archives and unarchives the workflow', async () => {
      const archived = { ...own, archivedAt: '2026-11-14T11:00:00Z' }
      let patched: unknown
      engine({
        'PATCH /projects/prj_1/workflows/wf_2': (request) => {
          patched = request.body
          return { status: 200, body: (request.body as { archived: boolean }).archived ? archived : own }
        },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      expect(await store.setArchived(true)).toBe(true)
      expect(patched).toEqual({ archived: true })
      expect(store.workflow?.archivedAt).toBe('2026-11-14T11:00:00Z')
      expect(store.notice).toBe('Archived nightly.')

      expect(await store.setArchived(false)).toBe(true)
      expect(store.workflow?.archivedAt).toBeUndefined()
      expect(store.notice).toBe('Unarchived nightly.')
    })

    it('says why a change was refused', async () => {
      engine({
        'PATCH /projects/prj_1/workflows/wf_2': { status: 409, body: errorBody('conflict', 'The name is in use.') },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      expect(await store.rename('dev-build')).toBe(false)
      expect(store.error).toBe('The name is in use.')
      expect(store.name).toBe('nightly')
      expect(store.busy).toBeNull()
    })

    it('deletes the workflow and opens the first of the rest', async () => {
      let deleted = false
      const seen = engine({
        'GET /projects/prj_1/workflows': () => ({
          status: 200,
          body: { workflows: deleted ? [summaries[0]] : summaries },
        }),
        'DELETE /projects/prj_1/workflows/wf_2': () => {
          deleted = true
          return { status: 204 }
        },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      expect(await store.remove()).toBe(true)

      expect(seen.some((request) => request.method === 'DELETE')).toBe(true)
      expect(store.workflows).toEqual([summaries[0]])
      expect(store.workflow?.id).toBe('wf_1')
      expect(store.notice).toBe('Deleted nightly.')
    })

    it('starts a draft once the last workflow is deleted, and keeps one the engine refuses to delete', async () => {
      let deletes = 0
      engine({
        'GET /projects/prj_1/workflows': () => ({ status: 200, body: { workflows: deletes > 1 ? [] : summaries } }),
        'DELETE /projects/prj_1/workflows/wf_2': () =>
          ++deletes === 1
            ? { status: 409, body: errorBody('conflict', 'Jobs ran it; archive it instead.') }
            : { status: 204 },
      })
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      expect(await store.remove()).toBe(false)
      expect(store.error).toBe('Jobs ran it; archive it instead.')
      expect(store.workflow?.id).toBe('wf_2')

      expect(await store.remove()).toBe(true)
      expect(store.workflow).toBeNull()
      expect(store.yaml).toBe(toYaml(draftTemplate))
      expect(store.notice).toBe('Deleted nightly.')
    })

    it('changes nothing of a built-in or a draft', async () => {
      const seen = engine()
      const store = useWorkflowBuilderStore()
      await store.start('prj_1', 'wf_1')
      const before = seen.length

      expect(await store.restoreVersion(1)).toBe(false)
      expect(await store.rename('x')).toBe(false)
      expect(await store.setArchived(true)).toBe(false)
      expect(await store.remove()).toBe(false)
      store.draft()
      expect(await store.remove()).toBe(false)
      expect(seen.filter((request) => request.path !== '/projects/prj_1/workflows/validate')).toHaveLength(before)
    })

    it('imports a YAML file as a draft offered the name of the file', async () => {
      engine()
      const store = useWorkflowBuilderStore()
      await store.start('prj_1')

      store.importYaml('release.yml', ownYaml)
      expect(store.workflow).toBeNull()
      expect(store.name).toBe('release')
      expect(store.yaml).toBe(ownYaml)
      expect(store.dirty).toBe(true)
      expect(store.document?.name).toBe('Nightly')

      store.importYaml('.YAML', 'stages: [\n')
      expect(store.name).toBeNull()
      expect(store.shapeIssues).not.toEqual([])
    })
  })
})
