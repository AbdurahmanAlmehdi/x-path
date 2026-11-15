import { type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { errorBody, meOf, stubEngine } from '@/testing/fetch'
import { projectOf, runOf, workflowSummaryOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

describe('ProjectView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(role: 'viewer' | 'developer' = 'developer', routes = {}) {
    return stubEngine({
      'GET /me': { status: 200, body: meOf(role, role === 'viewer' ? [] : ['develop']) },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /projects/prj_1': { status: 200, body: projectOf() },
      'GET /projects/prj_1/runs': { status: 200, body: { runs: [runOf()] } },
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [workflowSummaryOf()] } },
      ...routes,
    })
  }


  it('shows the apps, their flavors and the recent runs, with Dispatch for a developer', async () => {
    engine()
    ;({ app } = await openApp('/projects/prj_1'))

    expect(app.find('main h1').text()).toBe('acme/app')
    expect(app.find('main header p').text()).toBe('main · 1 app')
    expect(app.find('[data-testid="running"]').text()).toBe('1 running')
    expect(app.find('main h2').text()).toBe('app')
    expect(app.text()).toContain('Flutter 3.47.0')
    expect(app.text()).toContain('Android · iOS')
    const rows = app.findAll('tbody tr').map((row) => row.text())
    expect(rows[0]).toContain('com.acme.dev')
    expect(rows[1]).toContain('production')
    const dispatch = app.find('a.button.primary')
    expect(dispatch.text()).toBe('Dispatch…')
    expect(dispatch.attributes('href')).toBe('/projects/prj_1/dispatch')
    expect(app.find('a.run').text()).toContain('Dev build')
    expect(app.find('a[href="/projects/prj_1/runs"]').text()).toBe('All runs')
    expect(app.find('a[href="/projects/prj_1/releases"]').text()).toBe('Releases')
    expect(app.find('a[href="/projects/prj_1/tests"]').text()).toBe('Tests')
  })

  it('shows no Dispatch button to a viewer', async () => {
    engine('viewer')
    ;({ app } = await openApp('/projects/prj_1'))

    expect(app.find('main h1').text()).toBe('acme/app')
    expect(app.find('a.button.primary').exists()).toBe(false)
  })

  it('says when nothing runs, an app has no flavor, or there is no app', async () => {
    const project = projectOf()
    const [first] = project.profile.apps
    project.profile.apps = [
      { ...first!, flavors: [], flutterVersion: undefined, version: undefined, hasIos: false, hasAndroid: false },
    ]
    engine('developer', {
      'GET /projects/prj_1': { status: 200, body: project },
      'GET /projects/prj_1/runs': { status: 200, body: { runs: [] } },
    })
    ;({ app } = await openApp('/projects/prj_1'))

    expect(app.find('[data-testid="running"]').text()).toBe('Nothing running')
    expect(app.text()).toContain('Flutter not pinned')
    expect(app.text()).toContain('No flavor to show.')
    expect(app.text()).toContain('Nothing has run yet.')
  })

  it('says a project has no app', async () => {
    const project = projectOf()
    project.profile.apps = []
    engine('developer', { 'GET /projects/prj_1': { status: 200, body: project } })
    ;({ app } = await openApp('/projects/prj_1'))

    expect(app.find('main header p').text()).toBe('main · 0 apps')
    expect(app.text()).toContain('No Flutter app found.')
  })

  it('says when the project is gone, or could not be read', async () => {
    engine('developer', {
      'GET /projects/prj_1': { status: 404, body: errorBody('not_found', 'No.') },
    })
    ;({ app } = await openApp('/projects/prj_1'))
    expect(app.text()).toContain('This project is no longer on the engine.')
    app.unmount()

    engine('developer', {
      'GET /projects/prj_1': { status: 500, body: errorBody('internal', 'Broken.') },
    })
    setActivePinia(createPinia())
    ;({ app } = await openApp('/projects/prj_1'))
    expect(app.find('[role="alert"]').text()).toBe('Broken.')
  })
})
