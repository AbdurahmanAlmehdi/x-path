import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { errorBody, meOf, stubEngine } from '@/testing/fetch'
import { projectOf, runOf, workflowSummaryOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

describe('ProjectsView', () => {
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


  it('lists the projects, each leading to its page', async () => {
    engine()
    ;({ app } = await openApp('/projects'))

    const link = app.find('main a.project')
    expect(link.attributes('href')).toBe('/projects/prj_1')
    expect(link.text()).toContain('acme/app')
    expect(link.text()).toContain('github.com · main · 1 app')
  })

  it('counts the apps of a project', async () => {
    const project = projectOf()
    project.profile.apps = [project.profile.apps[0]!, { ...project.profile.apps[0]!, path: 'b' }]
    engine('developer', { 'GET /projects': { status: 200, body: { projects: [project] } } })
    ;({ app } = await openApp('/projects'))

    expect(app.find('main a.project').text()).toContain('2 apps')
  })

  it('says when there is no project yet', async () => {
    engine('developer', { 'GET /projects': { status: 200, body: { projects: [] } } })
    ;({ app } = await openApp('/projects'))

    expect(app.find('main h2').text()).toBe('No projects yet')
  })

  it('says why the projects could not be read', async () => {
    engine('developer', { 'GET /projects': { status: 500, body: errorBody('internal', 'Broken.') } })
    ;({ app } = await openApp('/projects'))

    expect(app.find('[role="alert"]').text()).toBe('Broken.')
  })

  it('shows a project added while it is open', async () => {
    const seen = engine()
    ;({ app } = await openApp('/projects'))

    openEventFeed().send('project.added', { projectId: 'prj_2' })
    await flushPromises()

    expect(seen.filter((request) => request.path === '/projects')).toHaveLength(2)
  })
})
