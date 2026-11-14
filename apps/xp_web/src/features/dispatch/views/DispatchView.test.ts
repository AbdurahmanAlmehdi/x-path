import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import type { Project, WorkflowInput } from '@/api/client'
import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import {
  planOf,
  projectOf,
  releaseOf,
  runOf,
  workflowOf,
  workflowSummaryOf,
} from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

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

const inputs: WorkflowInput[] = [
  { name: 'publish', type: 'boolean', required: false },
  { name: 'track', type: 'choice', options: ['internal', 'beta'], required: false },
  { name: 'release', type: 'release', required: false },
  { name: 'ids', type: 'json', required: false, description: 'Ids by flavor.', default: { dev: '1' } },
  { name: 'groups', type: 'json', required: false },
  { name: 'notes', type: 'string', required: true },
]

describe('DispatchView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, role = 'developer') {
    return stubEngine({
      'GET /me': { status: 200, body: meOf(role as 'developer', role === 'viewer' ? [] : ['develop']) },
      'GET /projects/prj_1': { status: 200, body: projectOf() },
      'GET /projects/prj_1/runs': { status: 200, body: { runs: [] } },
      'GET /projects/prj_1/workflows': {
        status: 200,
        body: { workflows: [workflowSummaryOf(), workflowSummaryOf({ id: 'wf_2', name: 'custom', title: undefined, builtin: false })] },
      },
      'GET /workflows/schema': { status: 200, body: schema },
      'GET /runs': { status: 200, body: { runs: [] } },
      'GET /projects/prj_1/workflows/wf_1': { status: 200, body: workflowOf() },
      'GET /projects/prj_1/workflows/wf_2': {
        status: 200,
        body: workflowOf({ id: 'wf_2', name: 'custom', builtin: false, inputs }),
      },
      'GET /releases': { status: 200, body: { releases: [releaseOf()] } },
      'POST /projects/prj_1/workflows/wf_1/dispatch': {
        status: 200,
        body: planOf({
          version: '1.3.0',
          currentVersion: '1.2.0+7',
          stages: [
            {
              name: 'build',
              gates: ['prod_release'],
              jobs: [
                { name: 'Build dev for android', capabilities: [], engineOnly: false, local: true },
                {
                  name: 'Build dev for ios',
                  capabilities: [],
                  engineOnly: false,
                  local: false,
                  runner: 'mac-mini',
                  waitReason: 'the runner is busy',
                  narrowing: ['CocoaPods'],
                },
              ],
            },
          ],
          skipped: [
            { name: 'Upload', stage: 'build', reason: 'no Firebase app', blocks: false },
            { name: 'Sign', stage: 'build', reason: 'no keystore', blocks: true },
          ],
        }),
      },
      'POST /projects/prj_1/workflows/wf_2/dispatch': { status: 200, body: planOf() },
      ...routes,
    })
  }

  async function open(path = '/projects/prj_1/dispatch') {
    let router
    ;({ app, router } = await openApp(path))
    await vi.waitFor(() => expect(app!.find('[data-testid="dispatch"]').exists()).toBe(true))
    await new Promise((resolve) => setTimeout(resolve))
    await flushPromises()
    return { app: app!, router: router! }
  }

  it('tells a viewer their role cannot dispatch, and asks the engine nothing', async () => {
    const seen = engine({}, 'viewer')
    ;({ app } = await openApp('/projects/prj_1/dispatch'))

    expect(app.text()).toContain('Your role cannot dispatch.')
    expect(app.find('[data-testid="dispatch"]').exists()).toBe(false)
    expect(seen.map((request) => request.path)).toEqual(['/me'])
  })

  it('previews where each job lands, the gates and what it leaves out', async () => {
    engine()
    const { app } = await open()

    expect(app.find('main header p').text()).toBe('acme/app')
    expect(app.find('[data-testid="will-run"]').text()).toBe('Will run · 2 jobs in 1 stage')
    expect(app.find('.attention').text()).toBe('Waits for approval: production release')
    const jobs = app.findAll('.stage li').map((job) => job.text())
    expect(jobs[0]).toContain('on the engine')
    expect(jobs[1]).toContain('on mac-mini · needs a Mac for iOS: CocoaPods · waits: the runner is busy')
    expect(app.findAll('.skipped li').map((job) => job.text())).toEqual([
      'Upload: skipped, no Firebase app',
      'Sign: cannot run, no keystore',
    ])
    expect(app.text()).toContain('1.3.0 · from 1.2.0 (7) in the pubspec of the commit')
    expect(app.find('[data-testid="dispatch"]').attributes('disabled')).toBeDefined()
    expect(app.find('[data-testid="dispatch"]').text()).toBe('Dispatch 2 jobs')
  })

  it('sends the flavors, platforms, version and ref picked', async () => {
    engine()
    const { app } = await open()
    const seen = engine()

    await app.findAll('input[type="checkbox"]').find((box) => box.element.parentElement?.textContent?.trim() === 'prod')!.setValue(true)
    await app.findAll('input[type="checkbox"]').find((box) => box.element.parentElement?.textContent?.trim() === 'iOS')!.setValue(false)
    await app.find('input[value="minor"]').setValue(true)
    await vi.waitFor(() => expect(seen.filter((request) => request.method === 'POST').length).toBeGreaterThan(0))
    await flushPromises()

    expect(seen.filter((request) => request.method === 'POST').at(-1)?.body).toMatchObject({
      flavors: ['dev', 'prod'],
      platforms: ['android'],
      bump: 'minor',
    })

    await app.find('input[aria-label="Version to release"]').setValue('2.0.0')
    await app.find('input[placeholder="branch, tag or commit"]').setValue('release/2')
    await vi.waitFor(
      () =>
        expect(seen.filter((request) => request.method === 'POST').at(-1)?.body).toMatchObject({
          ref: 'release/2',
          version: '2.0.0',
        }),
      { timeout: 2000 },
    )
  })

  it('takes every kind of input, and says when JSON does not parse', async () => {
    engine()
    const { app } = await open()
    await app.find('select').setValue('wf_2')
    await vi.waitFor(() => expect(app.findAll('.input')).toHaveLength(6))
    await flushPromises()

    expect(app.find('select').text()).toContain('custom')
    const boolean = app.find('#input-publish')
    expect((boolean.element as HTMLSelectElement).value).toBe('false')
    await boolean.setValue('true')
    await app.find('#input-track').setValue('beta')
    expect(app.find('#input-release').text()).toBe('1.1.0+6 · prod')
    await app.find('#input-release').setValue('1.1.0+6')
    expect((app.find('#input-ids').element as HTMLTextAreaElement).value).toBe('{"dev":"1"}')
    expect(app.text()).toContain('Ids by flavor.')
    await app.find('#input-groups').setValue('[')
    expect(app.find('.invalid').text()).toBe('Not valid JSON.')
    expect(app.find('#input-groups').attributes('aria-invalid')).toBe('true')
    await app.find('#input-groups').setValue('["qa"]')
    expect(app.find('.invalid').exists()).toBe(false)
    await app.find('#input-groups').setValue(' ')
    await app.find('#input-notes').setValue('Hello')
    expect(app.find('label[for="input-notes"]').text()).toBe('notes *')

    await vi.waitFor(() => expect(app.find('[data-testid="dispatch"]').text()).toBe('Dispatch 1 job'))
  })

  it('shows a typed JSON value as typed', async () => {
    engine({
      'GET /runs': {
        status: 200,
        body: { runs: [runOf({ workflowId: 'wf_2', request: { inputs: { groups: '[' } as never } })] },
      },
    })
    const { app } = await open()
    await vi.waitFor(() => expect(app.findAll('.input')).toHaveLength(6))

    expect((app.find('#input-groups').element as HTMLTextAreaElement).value).toBe('[')
  })

  it('dispatches and opens the run', async () => {
    engine({ 'POST /projects/prj_1/workflows/wf_1/dispatch': { status: 200, body: planOf() } })
    const { app, router } = await open()
    engine({
      'GET /me': { status: 200, body: meOf('developer', ['develop']) },
      'POST /projects/prj_1/workflows/wf_1/dispatch': { status: 202, body: runOf({ id: 'run_7' }) },
      'GET /runs/run_7': { status: 200, body: runOf({ id: 'run_7' }) },
    })

    await app.find('[data-testid="dispatch"]').trigger('click')

    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/runs/run_7'))
  })

  it('dispatches a ref the engine fetches first', async () => {
    engine({
      'POST /projects/prj_1/workflows/wf_1/dispatch': {
        status: 422,
        body: {
          error: { code: 'workflow_invalid', message: 'No "main" yet.', details: { reason: 'ref_unknown' } },
        },
      },
    })
    const { app } = await open()

    expect(app.find('.notice').text()).toBe('No "main" yet.')
    expect(app.find('[data-testid="dispatch"]').text()).toBe('Dispatch')
  })

  it('says when nothing would run', async () => {
    engine({ 'POST /projects/prj_1/workflows/wf_1/dispatch': { status: 200, body: planOf({ stages: [] }) } })
    const { app } = await open()

    expect(app.text()).toContain('Nothing would run for these flavors and platforms.')
  })

  it('offers the apps of a project with several', async () => {
    const project: Project = projectOf()
    project.profile.apps = [
      project.profile.apps[0]!,
      { ...project.profile.apps[0]!, name: 'admin', path: 'apps/admin', flavors: [], hasIos: false },
    ]
    const seen = engine({ 'GET /projects/prj_1': { status: 200, body: project } })
    const { app } = await open()

    const apps = app.findAll('select')[1]!
    expect(apps.text()).toContain('admin (apps/admin)')
    await apps.setValue('apps/admin')
    await vi.waitFor(() =>
      expect(seen.filter((request) => request.method === 'POST').at(-1)?.body).toMatchObject({ app: 'apps/admin' }),
    )
    expect(app.findAll('fieldset legend').map((legend) => legend.text())).not.toContain('Flavors')
  })

  it('says when the project has no workflow, or is gone', async () => {
    engine({ 'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [] } } })
    ;({ app } = await openApp('/projects/prj_1/dispatch'))
    await vi.waitFor(() => expect(app!.text()).toContain('The project has no workflow.'))
    app.unmount()

    setActivePinia(createPinia())
    engine({ 'GET /projects/prj_1': { status: 404, body: errorBody('not_found', 'No.') } })
    ;({ app } = await openApp('/projects/prj_1/dispatch'))
    await vi.waitFor(() => expect(app!.text()).toContain('This project is no longer on the engine.'))
    app.unmount()

    setActivePinia(createPinia())
    engine({ 'GET /projects/prj_1': { status: 500, body: errorBody('internal', 'Broken.') } })
    ;({ app } = await openApp('/projects/prj_1/dispatch'))
    await vi.waitFor(() => expect(app!.find('[role="alert"]').text()).toBe('Broken.'))
  })

  it('opens on the workflow the address names', async () => {
    engine()
    const { app } = await open('/projects/prj_1/dispatch?workflow=custom')

    await vi.waitFor(() => expect((app.find('select').element as HTMLSelectElement).value).toBe('wf_2'))
  })
})
