import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { projectOf, runOf, workflowSummaryOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'
import { eventually } from '@/testing/wait'

describe('RunsView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer> = {}) {
    return stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /runs': {
        status: 200,
        body: {
          runs: [
            runOf(),
            runOf({ id: 'run_2', projectId: 'prj_9', version: undefined, request: undefined, origin: undefined }),
          ],
        },
      },
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [workflowSummaryOf()] } },
      ...routes,
    })
  }

  it('lists the runs of every project, each with its project', async () => {
    const seen = engine()
    ;({ app } = await openApp('/runs'))

    const rows = app.findAll('a.run')
    expect(rows).toHaveLength(2)
    expect(rows[0]?.attributes('href')).toBe('/runs/run_1')
    expect(rows[0]?.text()).toContain('Dev build')
    expect(rows[0]?.text()).toContain('acme/app')
    expect(rows[0]?.text()).toContain('dev · android')
    expect(rows[0]?.text()).toContain('1.2.0 (8)')
    expect(rows[0]?.text()).toContain('Sam')
    expect(rows[1]?.text()).toContain('prj_9')
    expect(app.findAll('select')).toHaveLength(2)
    expect(seen.find((request) => request.path === '/runs')?.search).toBe('?limit=50')
  })

  it('filters by project, workflow and state in the address', async () => {
    engine()
    let router
    ;({ app, router } = await openApp('/runs'))

    await app.find('select').setValue('prj_1')
    await eventually(() => expect(router.currentRoute.value.query).toEqual({ project: 'prj_1' }))
    await flushPromises()
    expect(app.findAll('select')).toHaveLength(3)
    expect(app.findAll('select option').map((option) => option.text())).toContain('Dev build')

    await app.findAll('select')[1]!.setValue('wf_1')
    await eventually(() =>
      expect(router.currentRoute.value.query).toEqual({ project: 'prj_1', workflow: 'wf_1' }),
    )
    await app.findAll('select')[2]!.setValue('failed')
    await eventually(() => expect(router.currentRoute.value.query.state).toBe('failed'))

    await app.find('select').setValue('')
    await eventually(() => expect(router.currentRoute.value.query).toEqual({ state: 'failed' }))
  })

  it('shows the runs of one project, by its own address', async () => {
    const seen = engine({ 'GET /runs': { status: 200, body: { runs: [] } } })
    ;({ app } = await openApp('/projects/prj_1/runs?state=failed&state=running&workflow=wf_1'))
    await flushPromises()

    expect(app.find('main header a').text()).toBe('acme/app')
    expect(app.findAll('select')).toHaveLength(2)
    expect(app.text()).toContain('No run matches.')
    expect(seen.find((request) => request.path === '/runs')?.search).toBe(
      '?project=prj_1&workflow=wf_1&state=failed&limit=50',
    )
  })

  it('ignores a state it does not know, and says when nothing ran', async () => {
    const seen = engine({ 'GET /runs': { status: 200, body: { runs: [] } } })
    ;({ app } = await openApp('/projects/prj_2/runs?state=nope'))

    expect(app.find('main header a').text()).toBe('prj_2')
    expect(app.text()).toContain('Nothing has run yet.')
    expect(seen.find((request) => request.path === '/runs')?.search).toBe('?project=prj_2&limit=50')
  })

  it('shows older runs on request', async () => {
    const seen = engine({ 'GET /runs': { status: 200, body: { runs: [runOf()], next: 'run_1' } } })
    ;({ app } = await openApp('/runs'))

    await app.find('button.more').trigger('click')
    await flushPromises()

    expect(seen.filter((request) => request.path === '/runs').at(-1)?.search).toBe(
      '?limit=50&before=run_1',
    )
  })

  it('says why the runs could not be read', async () => {
    engine({ 'GET /runs': { status: 500, body: errorBody('internal', 'Broken.') } })
    ;({ app } = await openApp('/runs'))

    expect(app.find('[role="alert"]').text()).toBe('Broken.')
  })
})
