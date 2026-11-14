import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import type { Permission } from '@/api/client'
import { openApp } from '@/testing/app'
import { type Answer, meOf, stubEngine } from '@/testing/fetch'
import { approvalOf, projectOf, releaseOf, runOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

describe('ReleasesView', () => {
  let app: VueWrapper | undefined
  const notes = {
    releaseId: 'rel_1',
    version: '1.1.0',
    build: 6,
    from: 'v1.0.0+5',
    to: 'abcdef0',
    commits: 2,
    groups: [
      {
        type: 'feat',
        title: 'Features',
        items: [{ sha: 'aaa', description: 'pay with cards', scope: 'checkout', breaking: false }],
      },
    ],
    slack: '*Features*',
    whatsapp: 'Features',
  }
  const appleKey = {
    id: 'cred_1',
    projectId: 'prj_1',
    app: '.',
    flavor: 'prod',
    kind: 'asc_key',
    status: 'verified',
  }

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(
    routes: Record<string, Answer | (() => Answer)> = {},
    permissions: Permission[] = ['develop', 'decide_approval', 'release'],
  ) {
    return stubEngine({
      'GET /me': { status: 200, body: meOf('releaser', permissions) },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /projects/prj_1/credentials': { status: 200, body: { credentials: [appleKey] } },
      'GET /releases': {
        status: 200,
        body: { releases: [releaseOf({ prNumber: 12, prUrl: 'https://github.com/acme/app/pull/12' })] },
      },
      'GET /releases/rel_1/history': {
        status: 200,
        body: {
          events: [
            { kind: 'created', at: '2026-11-10T09:00:00Z' },
            { kind: 'patch', at: '2026-11-12T09:00:00Z', patchNumber: 1 },
          ],
        },
      },
      'GET /releases/rel_1/notes': { status: 200, body: notes },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  function labels() {
    return app!.findAll('button').map((each) => each.text())
  }

  it('shows the release with its lanes, timeline, notes, texts, pull request and patches', async () => {
    engine()
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    expect(app.find('main h1').text()).toBe('Release 1.1.0 (6)')
    expect(app.find('main header p').text()).toBe('app · prod · v1.1.0+6')
    expect(app.find('[data-testid="release-hero"]').text()).toBe('Live on both stores')
    expect(app.find('.reminder').text()).toContain('raise min_version_ios and min_version_android to 1.1.0')
    expect(app.find('[data-testid="merge-caption"]').text()).toBe('Both stores live')
    const lanes = app.findAll('.lane')
    expect(lanes.map((lane) => lane.find('h3').text())).toEqual(['App Store', 'Google Play'])
    // The engine reads the App Store through its key: its rollout can change.
    expect(lanes[0]!.find('[data-testid="rollout"]').text()).toContain('Pause')
    expect(lanes[1]!.find('[data-testid="rollout"]').exists()).toBe(false)
    expect(lanes[0]!.findAll('.steps li').map((step) => step.classes()).at(-1)).toContain('now')
    expect(app.text()).toContain('since v1.0.0+5 · 2 commits')
    expect(app.text()).toContain('checkout: pay with cards')
    expect(app.findAll('.timeline li').map((entry) => entry.find('.entry span').text())).toEqual([
      'Patch 1 published',
      'Release dispatched',
    ])
    expect(app.find('[data-testid="release-pr"]').text()).toContain('#12')
    expect(app.find('[data-testid="release-pr"]').text()).toContain(
      'Merging adds no tag: v1.1.0+6 was tagged when the build was recorded.',
    )
    expect(app.find('[data-testid="patches"]').text()).toContain('Patch 1 · Published')
    expect(app.find('a[href="/runs/run_1"]').text()).toBe('Open run')
  })

  it('asks the stores now, changes the rollout and moves a patch', async () => {
    const seen = engine({
      'POST /releases/rel_1/refresh': { status: 200, body: releaseOf() },
      'POST /releases/rel_1/rollout': { status: 202, body: runOf({ id: 'run_9' }) },
      'POST /releases/rel_1/patches/1/rollback': { status: 202, body: runOf({ id: 'run_10' }) },
      'GET /projects/prj_1/credentials': {
        status: 200,
        body: { credentials: [appleKey, { ...appleKey, id: 'cred_2', kind: 'play_sa' }] },
      },
    })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    await button('Refresh').trigger('click')
    await flushPromises()
    expect(seen.some((request) => request.path === '/releases/rel_1/refresh')).toBe(true)

    await button('Pause').trigger('click')
    await flushPromises()
    expect(seen.find((request) => request.path.endsWith('/rollout'))?.body).toEqual({ store: 'apple', action: 'pause' })
    expect(app.find('[role="status"]').text()).toBe('Rollout change requested: approve it to apply')

    const select = app.find('select[aria-label="Roll out to"]')
    await select.setValue('20')
    await flushPromises()
    expect(seen.filter((request) => request.path.endsWith('/rollout')).at(-1)?.body).toEqual({
      store: 'play',
      action: 'fraction',
      userFraction: 0.2,
    })
    await select.setValue('')
    await button('Halt').trigger('click')
    await flushPromises()
    expect(seen.filter((request) => request.path.endsWith('/rollout'))).toHaveLength(3)

    await button('Roll back').trigger('click')
    await flushPromises()
    expect(seen.some((request) => request.path === '/releases/rel_1/patches/1/rollback')).toBe(true)
  })

  it('marks a store it cannot read by hand, after asking', async () => {
    const reviewing = releaseOf({
      state: 'in_review',
      stores: [
        { store: 'apple', state: 'in_review', source: 'api' },
        { store: 'play', state: 'uploaded', source: 'upload' },
      ],
    })
    const seen = engine({
      'GET /releases': { status: 200, body: { releases: [reviewing] } },
      'POST /releases/rel_1/stores/play/status': { status: 200, body: reviewing },
    })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    const play = app.findAll('.lane')[1]!
    expect(play.find('.lane-badge').text()).toBe('Unknown')
    expect(play.text()).toContain('No Google Play service account for this flavor')
    expect(app.find('[data-testid="merge-caption"]').text()).toBe('App Store must go live and Mark Google Play live')

    await button('Mark live').trigger('click')
    expect(play.text()).toContain('Mark 1.1.0 (6) Published?')
    await button('Keep').trigger('click')
    await button('Mark live').trigger('click')
    await play.find('button.primary').trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.path.endsWith('/stores/play/status'))?.body).toEqual({ state: 'live' })
    expect(app.find('[role="status"]').text()).toBe('Store status saved')
  })

  it('builds a rejected version again, and opens its run', async () => {
    const rejected = releaseOf({
      state: 'rejected',
      stores: [
        { store: 'apple', state: 'rejected', source: 'api', changedAt: '2026-11-12T09:00:00Z' },
        { store: 'play', state: 'in_review', source: 'upload' },
      ],
    })
    engine({
      'GET /releases': { status: 200, body: { releases: [rejected] } },
      'POST /releases/rel_1/builds': { status: 202, body: runOf({ id: 'run_9' }) },
      'GET /runs/run_9': { status: 200, body: runOf({ id: 'run_9' }) },
    })
    let router
    ;({ app, router } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    expect(app.find('[data-testid="release-hero"]').text()).toBe('Rejected by App Store')
    expect(app.findAll('.lane')[1]!.text()).toContain('A new build replaces 6 here too')
    await button('New build, same version…').trigger('click')
    expect(app.text()).toContain('Build 1.1.0 again?')
    await button('Cancel').trigger('click')
    await button('New build, same version…').trigger('click')
    await button('Start new build').trigger('click')

    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/runs/run_9'))
  })

  it('merges a release live everywhere, and opens the merge run', async () => {
    engine({
      'GET /releases': { status: 200, body: { releases: [releaseOf({ mergeEnabled: true, prNumber: 12 })] } },
      'POST /releases/rel_1/merge': { status: 202, body: runOf({ id: 'run_8' }) },
      'GET /runs/run_8': { status: 200, body: runOf({ id: 'run_8' }) },
    })
    let router
    ;({ app, router } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    await button('Merge into main').trigger('click')

    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/runs/run_8'))
  })

  it('saves the store texts, and copies the notes', async () => {
    const writeText = vi.fn(async () => {})
    vi.stubGlobal('navigator', { ...navigator, clipboard: { writeText } })
    const seen = engine({
      'PUT /releases/rel_1/texts': { status: 200, body: releaseOf({ whatsNew: 'Cards.' }) },
    })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    expect(button('Save texts').attributes('disabled')).toBeDefined()
    await app.findAll('.texts textarea')[0]!.setValue('Cards.')
    await button('Save texts').trigger('click')
    await flushPromises()
    expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({ whatsNew: 'Cards.', whatToTest: '' })

    await button('Copy for Slack').trigger('click')
    await flushPromises()
    expect(writeText).toHaveBeenCalledWith('*Features*')
    expect(labels()).toContain('Copied')
  })

  it('shows a viewer the release with nothing to do', async () => {
    engine({}, [])
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    expect(app.find('main h1').text()).toBe('Release 1.1.0 (6)')
    expect(labels()).not.toContain('Refresh')
    expect(labels()).not.toContain('Merge into main')
    expect(labels()).not.toContain('Pause')
    expect(labels()).not.toContain('Save texts')
    expect(app.find('.texts textarea').attributes('disabled')).toBeDefined()
  })

  it('picks a release from the list', async () => {
    engine({
      'GET /releases': {
        status: 200,
        body: { releases: [releaseOf({ id: 'rel_2', version: '1.2.0', state: 'merged', headSha: undefined }), releaseOf()] },
      },
      'GET /releases/rel_2/history': { status: 200, body: { events: [] } },
    })
    let router
    ;({ app, router } = await openApp('/projects/prj_1/releases/rel_2'))
    await flushPromises()

    expect(app.find('main h1').text()).toBe('Release 1.2.0 (6)')
    expect(app.text()).toContain('The notes are ready once the release is tagged.')
    expect(labels()).not.toContain('Merge into main')
    await app.find('a.pick:not(.selected)').trigger('click')
    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/releases/rel_1'))
    await flushPromises()
    expect(app.find('main h1').text()).toBe('Release 1.1.0 (6)')
  })

  it('says there is no release yet, and how to start one', async () => {
    engine({ 'GET /releases': { status: 200, body: { releases: [] } } })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    expect(app.find('main h1').text()).toBe('Releases')
    expect(app.find('.empty').text()).toContain('No release yet')
    expect(app.find('a[href="/projects/prj_1/dispatch?workflow=prod-release"]').exists()).toBe(true)
  })

  it('says production releases need GitHub for a project elsewhere, and when a project is gone', async () => {
    engine({
      'GET /projects': { status: 200, body: { projects: [projectOf({ host: 'gitlab.com' })] } },
      'GET /releases': { status: 200, body: { releases: [] } },
    })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()
    expect(app.find('.empty').text()).toContain('do not run for a project on gitlab.com')
    app.unmount()

    setActivePinia(createPinia())
    engine({ 'GET /projects': { status: 200, body: { projects: [] } } })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()
    expect(app.text()).toContain('This project is no longer on the engine.')
  })

  it('lists the approvals of its runs on the timeline', async () => {
    engine({
      'GET /approvals': {
        status: 200,
        body: { approvals: [approvalOf({ runId: 'run_1', createdAt: '2026-11-13T09:00:00Z' })] },
      },
    })
    ;({ app } = await openApp('/projects/prj_1/releases'))
    await flushPromises()

    expect(app.find('.timeline li .entry span').text()).toBe(
      'Approval requested: Release 1.2.0 (8) to the stores',
    )
  })
})
