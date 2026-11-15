import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { projectOf, runOf, workflowSummaryOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'
import { eventually } from '@/testing/wait'

describe('RunView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer> = {}, role: 'viewer' | 'developer' = 'developer') {
    return stubEngine({
      'GET /me': { status: 200, body: meOf(role, role === 'viewer' ? [] : ['develop']) },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /runs/run_1': { status: 200, body: runOf() },
      'GET /runs/run_9': { status: 200, body: runOf({ id: 'run_9' }) },
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [workflowSummaryOf()] } },
      'POST /runs/run_1/cancel': { status: 200, body: runOf({ state: 'cancelled', jobs: [] }) },
      'POST /runs/run_1/run-again': { status: 202, body: runOf({ id: 'run_9' }) },
      ...routes,
    })
  }

  it('shows the run, who started it, and its jobs by stage', async () => {
    engine()
    ;({ app } = await openApp('/runs/run_1'))

    expect(app.find('main h1').text()).toBe('Dev build')
    expect(app.find('main .badge').text()).toBe('Running')
    expect(app.find('[data-testid="run-origin"]').text()).toBe('Sam')
    expect(app.text()).toContain('1.2.0 (8)')
    expect(app.text()).toContain('main · 0123456789ab')
    expect(app.find('dd a').text()).toBe('acme/app')
    expect(app.findAll('.stage h3').map((stage) => stage.text())).toEqual(['Stage 1', 'Stage 2'])
    expect(app.findAll('a.job').map((job) => job.attributes('href'))).toEqual([
      '/jobs/job_1',
      '/jobs/job_2',
    ])
  })

  it('shows what a run leaves out, and why a job ended', async () => {
    engine({
      'GET /runs/run_1': {
        status: 200,
        body: runOf({
          ref: undefined,
          version: undefined,
          request: undefined,
          origin: undefined,
          projectId: 'prj_2',
          jobs: [{ id: 'job_1', name: 'build', stage: 0, state: 'failed', message: 'No SDK.' }],
        }),
      },
    })
    ;({ app } = await openApp('/runs/run_1'))

    expect(app.find('[data-testid="run-origin"]').exists()).toBe(false)
    expect(app.find('dd a').text()).toBe('prj_2')
    expect(app.find('.message').text()).toBe('No SDK.')
    expect(app.findAll('.actions button').map((button) => button.text())).toEqual([
      'Re-run failed jobs',
      'Run again',
    ])

    await app.find('.actions button').trigger('click')
    await flushPromises()
    expect(app.find('[role="alert"]').exists()).toBe(true)
  })

  it('asks before it cancels, and cancels', async () => {
    const seen = engine()
    ;({ app } = await openApp('/runs/run_1'))

    const cancel = app.findAll('.actions button').find((button) => button.text() === 'Cancel')
    await cancel!.trigger('click')
    expect(app.find('.actions').text()).toContain('Cancel Dev build?')
    await app.findAll('.actions button').find((button) => button.text() === 'Keep running')!.trigger('click')
    expect(app.find('.actions').text()).not.toContain('Cancel Dev build?')

    await app.findAll('.actions button').find((button) => button.text() === 'Cancel')!.trigger('click')
    await app.find('button.danger').trigger('click')
    await flushPromises()

    expect(seen.at(-1)).toMatchObject({ method: 'POST', path: '/runs/run_1/cancel' })
    expect(app.find('main .badge').text()).toBe('Cancelled')
  })

  it('runs again and opens the new run', async () => {
    engine()
    let router
    ;({ app, router } = await openApp('/runs/run_1'))

    await app.findAll('.actions button').find((button) => button.text() === 'Run again')!.trigger('click')

    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/runs/run_9'))
  })

  it('says why the engine refused', async () => {
    engine({ 'POST /runs/run_1/run-again': { status: 403, body: errorBody('forbidden', 'No.') } })
    ;({ app } = await openApp('/runs/run_1'))

    await app.findAll('.actions button').find((button) => button.text() === 'Run again')!.trigger('click')
    await flushPromises()

    expect(app.find('[role="alert"]').text()).toBe('No.')
  })

  it('shows a viewer no action', async () => {
    engine({}, 'viewer')
    ;({ app } = await openApp('/runs/run_1'))

    expect(app.find('main h1').text()).toBe('Dev build')
    expect(app.find('.actions').exists()).toBe(false)
  })

  it('says when the run is not there', async () => {
    engine({ 'GET /runs/run_1': { status: 404, body: errorBody('not_found', 'No.') } })
    ;({ app } = await openApp('/runs/run_1'))

    expect(app.text()).toContain('This run is not on the engine.')
  })
})
