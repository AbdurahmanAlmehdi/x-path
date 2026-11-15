import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { projectOf, storageReportOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

import { categoryRule } from '../labels'

describe('StorageView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, admin = true) {
    return stubEngine({
      'GET /me': { status: 200, body: admin ? meOf() : meOf('viewer', []) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /storage': { status: 200, body: storageReportOf() },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  it('shows what the engine keeps, by category and by flavor', async () => {
    engine()
    ;({ app } = await openApp('/storage'))

    expect(app.find('[data-testid="storage-hero"]').text()).toBe('1.5 GB of 2.0 GB reclaimable')
    expect(app.text()).toContain('Builds past the newest 5 of each flavor')
    expect(app.text()).toContain('Logs of jobs older than 90 days')
    expect(app.text()).toContain('acme/app')
    expect(app.text()).toContain('7 builds · 14 files')
    expect(app.text()).toMatch(/Measured/)
  })

  it('frees the categories picked after the warning', async () => {
    let freed = false
    const seen = engine({
      'GET /storage': () => ({
        status: 200,
        body: freed
          ? storageReportOf({ categories: [{ category: 'artifacts', usedBytes: 500_000_000, reclaimableBytes: 0, items: 6 }] })
          : storageReportOf(),
      }),
      'POST /storage/free': () => {
        freed = true
        return {
          status: 200,
          body: { dryRun: false, categories: [{ category: 'artifacts', bytes: 1_500_000_000, items: 6 }], failures: [] },
        }
      },
    })
    ;({ app } = await openApp('/storage'))

    await button('Free up space…').trigger('click')
    const dialog = app.find('[role="dialog"]')
    expect(dialog.text()).toContain('It cannot be undone.')
    expect(dialog.text()).toContain('Artifacts · 1.5 GB')
    await dialog.find('input[type="checkbox"]').setValue(false)
    expect(button('Free 0 B').attributes('disabled')).toBeDefined()
    await dialog.find('input[type="checkbox"]').setValue(true)
    await button('Free 1.5 GB').trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.path === '/storage/free')?.body).toEqual({
      dryRun: false,
      categories: ['artifacts'],
    })
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(app.find('[data-testid="storage-notice"]').text()).toBe('Freed 1.5 GB')
    expect(button('Free up space…').attributes('disabled')).toBeDefined()
  })

  it('keeps the warning open with a refusal, and closes on Keep everything', async () => {
    engine({ 'POST /storage/free': { status: 403, body: errorBody('forbidden', 'Only an admin deletes.') } })
    ;({ app } = await openApp('/storage'))

    await button('Free up space…').trigger('click')
    await button('Free 1.5 GB').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('Only an admin deletes.')

    await button('Keep everything').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(app.find('main [role="alert"]').text()).toBe('Only an admin deletes.')
  })

  it('saves the retention, and refuses what is not a whole number of at least 1', async () => {
    const seen = engine({ 'PUT /storage/retention': { status: 200, body: { keepPerFlavor: 3, logDays: 30 } } })
    ;({ app } = await openApp('/storage'))

    const [keep, days] = app.findAll('form input[type="number"]')
    await keep!.setValue('0')
    expect(app.text()).toContain('Both need a whole number of at least 1.')
    expect(button('Save').attributes('disabled')).toBeDefined()
    await app.find('form.panel').trigger('submit')
    expect(seen.some((request) => request.method === 'PUT')).toBe(false)

    await keep!.setValue('3')
    await days!.setValue('30')
    await app.find('form.panel').trigger('submit')
    await flushPromises()

    expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({ keepPerFlavor: 3, logDays: 30 })
    expect(app.find('[data-testid="storage-notice"]').text()).toBe('Retention saved')
  })

  it('lets a viewer read, not free or save', async () => {
    engine({ 'GET /projects': { status: 200, body: { projects: [] } } }, false)
    ;({ app } = await openApp('/storage'))

    const labels = app.findAll('button').map((each) => each.text())
    expect(labels).toContain('Measure again')
    expect(labels).not.toContain('Free up space…')
    expect(labels).not.toContain('Save')
    expect(app.find('form input[type="number"]').attributes('readonly')).toBeDefined()
    expect(app.text()).toContain('prj_1')
  })

  it('says why the engine could not measure', async () => {
    engine({ 'GET /storage': { status: 500, body: errorBody('internal', 'Broken.') } })
    ;({ app } = await openApp('/storage'))

    expect(app.find('main [role="alert"]').text()).toBe('Broken.')
  })

  it('words every category', () => {
    const retention = { keepPerFlavor: 5, logDays: 90 }
    expect(categoryRule('worktrees', retention)).toBe('Worktrees of finished jobs')
    expect(categoryRule('mirrors', retention)).toBe('Mirrors of repositories that are no longer projects')
    expect(categoryRule('flutter', retention)).toBe("SDKs in XPath's cache that no project pins")
  })
})
