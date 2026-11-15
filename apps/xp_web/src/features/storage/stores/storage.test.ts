import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { storageReportOf } from '@/testing/fixtures'

import { useStorageStore } from './storage'

describe('useStorageStore', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('measures what the engine keeps and what it could give back', async () => {
    stubEngine({ 'GET /storage': { status: 200, body: storageReportOf() } })
    const store = useStorageStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.used).toBe(2_050_000_000)
    expect(store.reclaimable).toBe(1_500_000_000)
    expect(store.error).toBeNull()
  })

  it('counts nothing before it measured, and says why it could not', async () => {
    stubUnreachableEngine()
    const store = useStorageStore()
    expect(store.used).toBe(0)
    expect(store.reclaimable).toBe(0)

    await store.load()

    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('frees the categories picked, says how much, and measures again', async () => {
    const seen = stubEngine({
      'GET /storage': { status: 200, body: storageReportOf() },
      'POST /storage/free': {
        status: 200,
        body: {
          dryRun: false,
          categories: [{ category: 'artifacts', bytes: 1_500_000_000, items: 6 }],
          failures: ['Could not delete artifacts/old.apk.'],
        },
      },
    })
    const store = useStorageStore()

    expect(await store.free(['artifacts'])).toBe(true)

    expect(seen.find((request) => request.method === 'POST')?.body).toEqual({
      dryRun: false,
      categories: ['artifacts'],
    })
    expect(store.notice).toBe('Freed 1.5 GB')
    expect(store.failures).toEqual(['Could not delete artifacts/old.apk.'])
    expect(store.busy).toBeNull()
    expect(seen.filter((request) => request.method === 'GET')).toHaveLength(1)
  })

  it('says why freeing was refused', async () => {
    stubEngine({
      'POST /storage/free': { status: 403, body: errorBody('forbidden', 'Only an admin deletes.') },
    })
    const store = useStorageStore()

    expect(await store.free(['logs'])).toBe(false)
    expect(store.actionError).toBe('Only an admin deletes.')
  })

  it('saves the retention into the report, or says why not', async () => {
    let refuse = false
    stubEngine({
      'GET /storage': { status: 200, body: storageReportOf() },
      'PUT /storage/retention': () =>
        refuse
          ? { status: 400, body: errorBody('invalid_request', 'At least 1.') }
          : { status: 200, body: { keepPerFlavor: 3, logDays: 30 } },
    })
    const store = useStorageStore()
    expect(await store.saveRetention({ keepPerFlavor: 3, logDays: 30 })).toBe(true)
    expect(store.notice).toBe('Retention saved')

    await store.load()
    refuse = true
    expect(await store.saveRetention({ keepPerFlavor: 3, logDays: 30 })).toBe(false)
    expect(store.actionError).toBe('At least 1.')
  })

  it('puts the retention it saved into the report it has', async () => {
    let saved = false
    stubEngine({
      'GET /storage': () =>
        saved
          ? { status: 500, body: errorBody('internal', 'Broken.') }
          : { status: 200, body: storageReportOf() },
      'PUT /storage/retention': () => {
        saved = true
        return { status: 200, body: { keepPerFlavor: 2, logDays: 7 } }
      },
    })
    const store = useStorageStore()
    await store.load()

    await store.saveRetention({ keepPerFlavor: 2, logDays: 7 })

    expect(store.report?.retention).toEqual({ keepPerFlavor: 2, logDays: 7 })
  })
})
