import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { baselineOf, jobOf, projectOf, testRunOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'
import { eventually } from '@/testing/wait'

describe('TestsView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, role: 'viewer' | 'developer' = 'developer') {
    return stubEngine({
      'GET /me': { status: 200, body: meOf(role, role === 'viewer' ? [] : ['develop']) },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /projects/prj_1/tests/baseline': { status: 200, body: { baselines: [baselineOf()] } },
      'GET /jobs/job_1/tests': {
        status: 200,
        body: {
          ...testRunOf({
            id: 'tr_1',
            jobId: 'job_1',
            baseline: true,
            diff: { newFailures: [], fixed: [], missing: [], stillFailing: 0 },
          }),
          tests: [],
          total: 0,
        },
      },
      'GET /jobs/job_2/tests': { status: 200, body: testRunOf() },
      'GET /jobs/job_2': {
        status: 200,
        body: jobOf({
          steps: [
            { ordinal: 0, kind: 'test', state: 'succeeded', sideEffect: false, attempts: 1, startedAt: '2026-11-14T09:00:00Z', finishedAt: '2026-11-14T09:00:42Z' },
          ],
        }),
      },
      ...routes,
    })
  }

  it('shows a run against its baseline, new failures first', async () => {
    engine()
    ;({ app } = await openApp('/projects/prj_1/tests?job=job_2'))
    await flushPromises()

    expect(app.find('main h1').text()).toBe('Tests')
    expect(app.find('main header p').text()).toBe('app · main')
    expect(app.find('[data-testid="tests-hero"]').text()).toBe('1 new failure')
    expect(app.text()).toContain('42s')
    expect(app.text()).toContain('Compared with the baseline of main from')
    expect(app.findAll('.stat').map((stat) => stat.text())).toEqual([
      '1new failures',
      '1in baseline',
      '1fixed',
      '7passed',
      '2failed',
      '0errored',
      '1skipped',
    ])
    expect(app.findAll('.panel h2').map((title) => title.text())).toEqual([
      'New failures 1',
      'Failing in the baseline too 1',
      'Fixed since the baseline 1',
      'Baselines',
    ])
    expect(app.find('.tests li').text()).toContain('a breaks')
    expect(app.find('.message').text()).toBe('Expected: 1')
    expect(app.findAll('.label').map((label) => label.text())).toEqual(['Failed', 'Errored', 'Fixed'])
    expect(app.find('a[href="/jobs/job_2"]').text()).toBe('Open job')
  })

  it('picks another run, and shows a baseline that passed', async () => {
    engine()
    let router
    ;({ app, router } = await openApp('/projects/prj_1/tests?job=job_2'))
    await flushPromises()

    await app.find('[data-testid="baselines"] button').trigger('click')
    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/tests?job=job_1'))
    await flushPromises()

    expect(app.find('[data-testid="tests-hero"]').text()).toBe('No new failures')
    expect(app.text()).toContain('This run is the baseline of main')
    expect(app.text()).toContain('Every test passed and nothing changed against the baseline.')
    expect(app.find('[data-testid="baselines"] button').attributes('disabled')).toBeDefined()
    expect(app.findAll('.pick').map((pick) => pick.text())).toHaveLength(2)

    await app.findAll('.pick')[1]!.trigger('click')
    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/tests?job=job_2'))
  })

  it('says when there is no baseline yet, and when a page of tests is cut', async () => {
    engine({
      'GET /jobs/job_2/tests': {
        status: 200,
        body: {
          ...testRunOf({ appPath: 'apps/shop', diff: { newFailures: [], fixed: [], missing: [{ suite: 'test/d_test.dart', name: 'd' }], stillFailing: 2 } }),
          total: 300,
        },
      },
      'GET /projects/prj_1/tests/baseline': { status: 200, body: { baselines: [] } },
    })
    ;({ app } = await openApp('/projects/prj_1/tests?job=job_2'))
    await flushPromises()

    expect(app.find('main header p').text()).toBe('app · apps/shop · main')
    expect(app.text()).toContain('No baseline yet, so every failure counts as new')
    expect(app.text()).toContain('Showing 2 of 300 failing tests.')
    expect(app.text()).toContain('In the baseline, not in this run')
    expect(app.findAll('.stat').at(-1)?.text()).toBe('1missing')
  })

  it('names the baseline job when the project no longer has that baseline', async () => {
    engine({ 'GET /projects/prj_1/tests/baseline': { status: 200, body: { baselines: [baselineOf({ jobId: 'job_0' })] } } })
    ;({ app } = await openApp('/projects/prj_1/tests?job=job_2'))
    await flushPromises()

    expect(app.text()).toContain('Compared with the baseline run of job_1')
  })

  it('says there are no runs yet, and how to start one', async () => {
    engine({ 'GET /projects/prj_1/tests/baseline': { status: 200, body: { baselines: [] } } })
    ;({ app } = await openApp('/projects/prj_1/tests'))
    await flushPromises()

    expect(app.find('.empty').text()).toContain('No test runs yet')
    expect(app.find('a[href="/projects/prj_1/dispatch?workflow=test"]').text()).toBe('Run Tests…')
  })

  it('says why a run could not be read, and when the project is gone', async () => {
    engine({ 'GET /jobs/job_9/tests': { status: 404, body: errorBody('not_found', 'No test run.') } }, 'viewer')
    ;({ app } = await openApp('/projects/prj_1/tests?job=job_9'))
    await flushPromises()
    expect(app.find('[role="alert"]').text()).toBe('No test run.')
    app.unmount()

    setActivePinia(createPinia())
    engine({ 'GET /projects': { status: 200, body: { projects: [] } } })
    ;({ app } = await openApp('/projects/prj_1/tests'))
    await flushPromises()
    expect(app.text()).toContain('This project is no longer on the engine.')
  })
})
