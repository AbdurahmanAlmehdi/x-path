import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import type { Job } from '@/api/client'
import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { jobOf } from '@/testing/fixtures'
import { FakeSocket, openEventFeed, stubSockets } from '@/testing/sockets'

const line = (seq: number, stream = 'stdout') => ({
  type: 'line',
  seq,
  step: 1,
  at: '2026-11-14T09:00:00Z',
  stream,
  text: `\u001b[1mline ${seq}\u001b[0m`,
})

function logSocket(): FakeSocket {
  const socket = [...FakeSocket.opened].reverse().find((each) => each.path.includes('/logs'))
  if (!socket) throw new Error('No log socket.')
  return socket
}

describe('JobView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(job: Partial<Job> = {}, routes: Record<string, Answer> = {}, role = 'developer') {
    return stubEngine({
      'GET /me': { status: 200, body: meOf(role as 'developer', role === 'viewer' ? [] : ['develop']) },
      'GET /jobs/job_2': { status: 200, body: jobOf(job) },
      'POST /jobs/job_2/cancel': { status: 200, body: jobOf({ state: 'cancelled' }) },
      'POST /jobs/job_2/resume': { status: 202, body: jobOf({ state: 'queued' }) },
      ...routes,
    })
  }

  it('shows the job, its steps and its live log', async () => {
    engine()
    ;({ app } = await openApp('/jobs/job_2'))

    expect(app.find('main h1').text()).toBe('Build dev for android')
    expect(app.find('main header a').attributes('href')).toBe('/runs/run_1')
    const steps = app.findAll('.step').map((step) => step.text())
    expect(steps[0]).toContain('Check out')
    expect(steps[0]).toContain('2s')
    expect(steps[1]).toContain('Build Android')
    expect(app.find('.empty').text()).toBe('No output yet')

    logSocket().open().send(line(1)).send(line(2, 'stderr'))
    await flushPromises()

    expect(app.findAll('.line .text').map((text) => text.text())).toEqual(['line 1', 'line 2'])
    expect(app.findAll('.line.stderr')).toHaveLength(1)
    expect(app.find('[data-testid="log-count"]').text()).toBe('2 lines · live')
    expect(app.findAll('.actions button').map((button) => button.text())).toEqual(['Cancel'])
  })

  it('says when the log ended, and follows it again when the job is resumed', async () => {
    engine({ state: 'interrupted', steps: [{ ordinal: 0, kind: 'command', state: 'interrupted', sideEffect: false, attempts: 1 }] })
    ;({ app } = await openApp('/jobs/job_2'))
    const feed = openEventFeed()
    logSocket().open().send(line(1)).send({ type: 'end', state: 'interrupted' })
    await flushPromises()

    expect(app.find('.ended').text()).toBe('The log ended: Interrupted.')
    expect(app.find('[data-testid="log-count"]').text()).toBe('1 line')
    expect(app.find('[data-testid="job-band"]').text()).toContain('The engine stopped while this job ran.')

    await app.findAll('.actions button').find((button) => button.text() === 'Resume')!.trigger('click')
    await flushPromises()

    expect(logSocket().path).toBe('/api/v1/jobs/job_2/logs?after=1')
    feed.send('job.state_changed', { jobId: 'job_2' })
    await flushPromises()
  })

  it('says why a job waits for a resume, failed or waits to start', async () => {
    engine({
      state: 'waiting_for_resume',
      steps: [{ ordinal: 0, kind: 'upload.play', state: 'interrupted', sideEffect: true, attempts: 1 }],
    })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.find('[data-testid="job-band"]').text()).toContain(
      'The engine stopped during Upload to Google Play',
    )
    app.unmount()

    setActivePinia(createPinia())
    engine({ state: 'waiting_for_resume', steps: [] })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.find('[data-testid="job-band"]').text()).toContain('during a step')
    app.unmount()

    setActivePinia(createPinia())
    engine({ state: 'failed', message: 'No SDK.' })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.find('[data-testid="job-band"]').text()).toBe('No SDK.')
    app.unmount()

    setActivePinia(createPinia())
    engine({ state: 'cancelled' })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.find('[data-testid="job-band"]').exists()).toBe(false)
    app.unmount()

    setActivePinia(createPinia())
    engine({ state: 'queued', message: 'no runner has android' })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.find('[data-testid="job-band"]').text()).toBe('Waiting: no runner has android')
    expect(app.find('main h1').exists()).toBe(true)
  })

  it('cancels the job', async () => {
    const seen = engine()
    ;({ app } = await openApp('/jobs/job_2'))

    await app.findAll('.actions button').find((button) => button.text() === 'Cancel')!.trigger('click')
    await flushPromises()

    expect(seen.at(-1)).toMatchObject({ method: 'POST', path: '/jobs/job_2/cancel' })
    expect(app.find('main .badge').text()).toBe('Cancelled')
  })

  it('shows a viewer no action, and a job without a name or a run', async () => {
    engine({ name: undefined, runId: undefined }, {}, 'viewer')
    ;({ app } = await openApp('/jobs/job_2'))

    expect(app.find('main h1').text()).toBe('Job')
    expect(app.find('.actions').exists()).toBe(false)
  })

  it('says when the job is not there, or could not be read', async () => {
    engine({}, { 'GET /jobs/job_2': { status: 404, body: errorBody('not_found', 'No.') } })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.text()).toContain('This job is not on the engine.')
    app.unmount()

    setActivePinia(createPinia())
    engine({}, { 'GET /jobs/job_2': { status: 500, body: errorBody('internal', 'Broken.') } })
    ;({ app } = await openApp('/jobs/job_2'))
    expect(app.find('[role="alert"]').text()).toBe('Broken.')
  })

  it('leads to the test results of a job that ran its tests, and to the approval it waits for', async () => {
    engine({
      state: 'waiting_for_approval',
      steps: [
        { ordinal: 0, kind: 'test', state: 'succeeded', sideEffect: false, attempts: 1 },
        { ordinal: 1, kind: 'gate', state: 'waitingForApproval', sideEffect: false, attempts: 1 },
      ],
    })
    ;({ app } = await openApp('/jobs/job_2'))

    expect(app.find('a[href="/projects/prj_1/tests?job=job_2"]').text()).toBe('Test results')
    expect(app.find('main a[href="/approvals"]').text()).toBe('Review the approval')
  })
})
