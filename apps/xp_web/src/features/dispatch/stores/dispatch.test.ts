import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { type Answer, errorBody, stubEngine } from '@/testing/fetch'
import {
  planOf,
  projectOf,
  releaseOf,
  runOf,
  workflowOf,
  workflowSummaryOf,
} from '@/testing/fixtures'

import { releaseValue, typingPause, useDispatchStore } from './dispatch'

const schema = {
  schema: 1,
  steps: [],
  gates: ['prod_release'],
  gateLabels: { prod_release: 'production release' },
  capabilities: [],
  matrixAxes: [],
  platforms: ['android', 'ios'],
  variables: [],
}

const workflows = [
  workflowSummaryOf(),
  workflowSummaryOf({ id: 'wf_2', name: 'prod-release', title: 'Production release' }),
  workflowSummaryOf({ id: 'wf_3', name: 'release-merge' }),
  workflowSummaryOf({ id: 'wf_4', name: 'old', builtin: false, archivedAt: '2026-11-01T00:00:00Z' }),
]

type Routes = Record<string, Answer | (() => Answer)>

function engine(routes: Routes = {}) {
  return stubEngine({
    'GET /projects/prj_1/workflows': { status: 200, body: { workflows } },
    'GET /workflows/schema': { status: 200, body: schema },
    'GET /runs': { status: 200, body: { runs: [] } },
    'GET /projects/prj_1/workflows/wf_1': { status: 200, body: workflowOf() },
    'GET /projects/prj_1/workflows/wf_2': {
      status: 200,
      body: workflowOf({ id: 'wf_2', name: 'prod-release' }),
    },
    'POST /projects/prj_1/workflows/wf_1/dispatch': { status: 200, body: planOf() },
    'POST /projects/prj_1/workflows/wf_2/dispatch': { status: 200, body: planOf() },
    ...routes,
  })
}

async function settle() {
  await vi.runAllTimersAsync()
  await flushPromises()
}

describe('useDispatchStore', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setActivePinia(createPinia())
  })
  afterEach(() => vi.useRealTimers())

  async function started(routes: Routes = {}, workflowId?: string) {
    const seen = engine(routes)
    const store = useDispatchStore()
    await store.start(projectOf(), workflowId)
    await settle()
    return { store, seen }
  }

  describe('start', () => {
    it('offers the workflows to dispatch, picks the first and previews it', async () => {
      const { store, seen } = await started()

      expect(store.loading).toBe(false)
      expect(store.workflows.map((each) => each.id)).toEqual(['wf_1', 'wf_2'])
      expect(store.workflow?.id).toBe('wf_1')
      expect(store.gitRef).toBe('main')
      expect(store.app).toBe('.')
      expect(store.preview).toEqual(planOf())
      expect(store.jobCount).toBe(1)
      expect(store.canDispatch).toBe(true)
      const planned = seen.find((request) => request.method === 'POST')
      expect(planned?.search).toBe('?dryRun=true')
      expect(planned?.body).toEqual({ app: '.', ref: 'main', inputs: {} })
    })

    it('picks the workflow asked for, by id or by name', async () => {
      const { store } = await started({}, 'wf_2')
      expect(store.workflow?.id).toBe('wf_2')

      await store.start(projectOf(), 'prod-release')
      await settle()
      expect(store.workflow?.id).toBe('wf_2')
    })

    it('picks the workflow dispatched last, with the inputs of its last run', async () => {
      const { store } = await started({
        'GET /runs': {
          status: 200,
          body: { runs: [runOf({ workflowId: 'wf_2', request: { inputs: { notes: 'hi' } as never } })] },
        },
      })

      expect(store.workflow?.id).toBe('wf_2')
      expect(store.inputs).toEqual({ notes: 'hi' })
    })

    it('asks for the schema once', async () => {
      const { store, seen } = await started()

      await store.start(projectOf())
      await settle()

      expect(seen.filter((request) => request.path === '/workflows/schema')).toHaveLength(1)
    })

    it('says so when the project has no workflow', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [] } },
      })

      expect(store.workflow).toBeNull()
      expect(store.canDispatch).toBe(false)
    })

    it('says why the workflows could not be read', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows': { status: 500, body: errorBody('internal', 'Broken.') },
      })

      expect(store.error).toBe('Broken.')
      expect(store.loading).toBe(false)
    })

    it('carries on without the last run when it cannot be read', async () => {
      const { store } = await started({ 'GET /runs': { status: 500 } })

      expect(store.workflow?.id).toBe('wf_1')
    })

    it('takes the first app, or the root without one', async () => {
      engine()
      const store = useDispatchStore()
      const project = projectOf()
      project.profile.apps = []

      await store.start(project)
      await settle()

      expect(store.app).toBe('.')
      expect(store.chosenApp).toBeNull()
    })
  })

  describe('choose', () => {
    it('says why the workflow could not be read', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows/wf_2': { status: 404, body: errorBody('not_found', 'Gone.') },
      })

      await store.choose('wf_2')
      await settle()

      expect(store.error).toBe('Gone.')
      expect(store.previewing).toBe(false)
    })

    it('keeps only the newest of two workflows picked at once', async () => {
      const { store } = await started()

      const first = store.choose('wf_2')
      const second = store.choose('wf_1')
      await first
      await second
      await settle()

      expect(store.workflow?.id).toBe('wf_1')
    })

    it('drops the failure of a workflow picked before another', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows/wf_2': { status: 500, body: errorBody('internal', 'Broken.') },
      })

      const first = store.choose('wf_2')
      const second = store.choose('wf_1')
      await first
      await second
      await settle()

      expect(store.error).toBeNull()
    })

    it('does nothing before the form starts', async () => {
      const store = useDispatchStore()

      await store.choose('wf_1')

      expect(store.workflow).toBeNull()
    })

    it('offers the releases that reached a store for a release input, newest first', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows/wf_2': {
          status: 200,
          body: workflowOf({
            id: 'wf_2',
            inputs: [{ name: 'release', type: 'release', required: true }],
          }),
        },
        'GET /releases': {
          status: 200,
          body: {
            releases: [
              releaseOf({ id: 'rel_1', version: '1.0.0', createdAt: '2026-11-01T00:00:00Z' }),
              releaseOf({ id: 'rel_2', version: '1.1.0', createdAt: '2026-11-05T00:00:00Z' }),
              releaseOf({ id: 'rel_3', version: '1.2.0', state: 'draft' }),
            ],
          },
        },
      })

      await store.choose('wf_2')
      await settle()

      expect(store.releases?.map((release) => release.id)).toEqual(['rel_2', 'rel_1'])
      expect(store.inputs).toEqual({ release: '1.1.0+6' })
      expect(store.request.releaseVersion).toBe('1.1.0+6')
      expect(store.noReleases).toBe(false)
    })

    it('cannot dispatch a workflow that needs a release when there is none', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows/wf_2': {
          status: 200,
          body: workflowOf({
            id: 'wf_2',
            inputs: [{ name: 'release', type: 'release', required: true }],
          }),
        },
        'GET /releases': { status: 200, body: { releases: [] } },
      })

      await store.choose('wf_2')
      await settle()

      expect(store.noReleases).toBe(true)
      expect(store.inputs).toEqual({})
      expect(store.canDispatch).toBe(false)
    })
  })

  describe('preview', () => {
    it('says the engine fetches a ref it does not have yet, and can still dispatch', async () => {
      const { store } = await started({
        'POST /projects/prj_1/workflows/wf_1/dispatch': {
          status: 422,
          body: {
            error: {
              code: 'workflow_invalid',
              message: 'This engine has no "main" yet.',
              details: { reason: 'ref_unknown' },
            },
          },
        },
      })

      expect(store.preview).toBeNull()
      expect(store.refNotice).toBe('This engine has no "main" yet.')
      expect(store.error).toBeNull()
      expect(store.canDispatch).toBe(true)
    })

    it('says why the engine cannot plan the dispatch', async () => {
      const { store } = await started({
        'POST /projects/prj_1/workflows/wf_1/dispatch': {
          status: 422,
          body: errorBody('workflow_invalid', 'No such flavor.'),
        },
      })

      expect(store.error).toBe('No such flavor.')
      expect(store.refNotice).toBeNull()
      expect(store.canDispatch).toBe(false)
    })

    it('cannot dispatch a plan that is blocked or runs nothing', async () => {
      const { store } = await started({
        'POST /projects/prj_1/workflows/wf_1/dispatch': {
          status: 200,
          body: planOf({ skipped: [{ name: 'build', stage: 'build', reason: 'no runner', blocks: true }] }),
        },
      })
      expect(store.blocked).toBe(true)
      expect(store.canDispatch).toBe(false)

      engine({
        'POST /projects/prj_1/workflows/wf_1/dispatch': { status: 200, body: planOf({ stages: [] }) },
      })
      store.toggleFlavor('prod')
      await settle()
      expect(store.jobCount).toBe(0)
      expect(store.canDispatch).toBe(false)
    })

    it('lists the gates by their labels', async () => {
      const { store } = await started({
        'POST /projects/prj_1/workflows/wf_1/dispatch': {
          status: 200,
          body: planOf({
            stages: [
              { name: 'a', gates: ['prod_release'], jobs: [] },
              { name: 'b', gates: ['prod_release', 'push'], jobs: [] },
            ],
          }),
        },
      })

      expect(store.gates).toEqual(['prod_release', 'push'])
      expect(store.gates.map(store.gateLabel)).toEqual(['production release', 'push'])
    })

    it('plans once after typing pauses, and keeps only the newest plan', async () => {
      const { store, seen } = await started()
      seen.length = 0

      store.setRef('feat/a')
      store.setRef('feat/ab')
      expect(store.previewing).toBe(true)
      await vi.advanceTimersByTimeAsync(typingPause - 1)
      expect(seen).toHaveLength(0)
      await settle()

      expect(seen).toHaveLength(1)
      expect(seen[0]?.body).toMatchObject({ ref: 'feat/ab' })
      expect(store.previewing).toBe(false)
    })

    it('plans nothing once stopped, nor once the store is disposed', async () => {
      const { store, seen } = await started()
      seen.length = 0

      store.setRef('feat/a')
      store.stop()
      expect(store.previewing).toBe(false)
      await settle()
      expect(seen).toHaveLength(0)

      store.setRef('feat/b')
      store.$dispose()
      await settle()
      expect(seen).toHaveLength(0)
    })

    it('drops a plan that a newer change outran', async () => {
      let answers = 0
      const { store } = await started({
        'POST /projects/prj_1/workflows/wf_1/dispatch': () => {
          answers += 1
          return answers === 2
            ? { status: 500, body: errorBody('internal', 'Old.') }
            : { status: 200, body: planOf() }
        },
      })

      store.setBump('minor')
      await vi.advanceTimersByTimeAsync(0)
      store.setBump('major')
      await settle()

      expect(store.error).toBeNull()
      expect(store.preview).toEqual(planOf())
    })

    it('does not plan without a workflow', async () => {
      const seen = engine()
      const store = useDispatchStore()

      store.setRef('main')
      await settle()

      expect(seen).toHaveLength(0)
      expect(store.previewing).toBe(false)
    })
  })

  describe('what it sends', () => {
    it('sends the flavors and platforms picked, from the default ones', async () => {
      const { store } = await started()

      store.toggleFlavor('prod')
      store.togglePlatform('ios')
      await settle()

      expect(store.chosenFlavors).toEqual(['dev', 'prod'])
      expect(store.request.flavors).toEqual(['dev', 'prod'])
      expect(store.request.platforms).toEqual(['android'])

      store.toggleFlavor('dev')
      expect(store.request.flavors).toEqual(['prod'])
    })

    it('forgets the flavors and platforms picked for another app', async () => {
      const { store } = await started()
      store.toggleFlavor('prod')

      store.chooseApp('packages/other')
      await settle()

      expect(store.app).toBe('packages/other')
      expect(store.flavors).toBeNull()
      expect(store.platforms).toBeNull()
    })

    it('sends the bump, or the version typed, only for a workflow that writes one', async () => {
      const { store } = await started()
      store.setBump('minor')
      await settle()
      expect(store.bumps).toBe(false)
      expect(store.request.bump).toBeUndefined()

      engine({
        'POST /projects/prj_1/workflows/wf_1/dispatch': {
          status: 200,
          body: planOf({ version: '1.3.0', currentVersion: '1.2.0+7' }),
        },
      })
      store.setBump('minor')
      await settle()
      expect(store.request).toMatchObject({ bump: 'minor' })

      store.setVersion(' 2.0.0 ')
      await settle()
      expect(store.request.version).toBe('2.0.0')
      expect(store.request.bump).toBeUndefined()
    })

    it('leaves the ref out when it is empty', async () => {
      const { store } = await started()

      store.setRef('  ')

      expect(store.request.ref).toBeUndefined()
    })

    it('sends the inputs set, and the first option of a choice without a default', async () => {
      const { store } = await started({
        'GET /projects/prj_1/workflows/wf_1': {
          status: 200,
          body: workflowOf({
            inputs: [
              { name: 'track', type: 'choice', options: ['internal', 'beta'], required: false },
              { name: 'lane', type: 'choice', options: ['a', 'b'], default: 'b', required: false },
              { name: 'notes', type: 'string', required: false },
              { name: 'ids', type: 'json', required: false },
            ],
          }),
        },
      })

      store.setInput('notes', 'hello', { typed: true })
      expect(store.request.inputs).toEqual({ track: 'internal', notes: 'hello' })

      store.setInput('ids', '{', { valid: false, typed: true })
      expect(store.invalidInputs).toEqual(['ids'])
      expect(store.canDispatch).toBe(false)
      store.setInput('ids', '{', { valid: false, typed: true })
      expect(store.invalidInputs).toEqual(['ids'])

      store.setInput('ids', { dev: '1' })
      expect(store.invalidInputs).toEqual([])
      await settle()
    })
  })

  describe('submit', () => {
    it('dispatches the run it previews', async () => {
      const { store, seen } = await started()
      engine({ 'POST /projects/prj_1/workflows/wf_1/dispatch': { status: 202, body: runOf() } })

      const run = store.submit()
      expect(store.submitting).toBe(true)
      expect(await run).toEqual(runOf())

      expect(store.submitting).toBe(false)
      expect(seen.at(-1)?.search).toBe('?dryRun=true')
    })

    it('says why the engine refused', async () => {
      const { store } = await started()
      engine({
        'POST /projects/prj_1/workflows/wf_1/dispatch': {
          status: 403,
          body: errorBody('forbidden', 'Viewers cannot dispatch.'),
        },
      })

      expect(await store.submit()).toBeNull()
      expect(store.error).toBe('Viewers cannot dispatch.')
    })

    it('does not dispatch what it cannot', async () => {
      const store = useDispatchStore()

      expect(await store.submit()).toBeNull()
    })
  })

  it('writes a release as a release input takes it', () => {
    expect(releaseValue({ version: '1.2.0', build: 9 })).toBe('1.2.0+9')
  })
})
