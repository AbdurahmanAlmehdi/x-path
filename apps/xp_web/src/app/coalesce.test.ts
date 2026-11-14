import { describe, expect, it } from 'vitest'

import { coalesced } from './coalesce'

function deferred() {
  let resolve!: () => void
  let reject!: (error: Error) => void
  const promise = new Promise<void>((done, fail) => {
    resolve = done
    reject = fail
  })
  return { promise, resolve, reject }
}

describe('coalesced', () => {
  it('loads once more after a load under way, however many calls came', async () => {
    const loads: Array<ReturnType<typeof deferred>> = []
    const load = coalesced(() => {
      const next = deferred()
      loads.push(next)
      return next.promise
    })

    const first = load()
    const second = load()
    const third = load()
    expect(second).toBe(third)
    expect(loads).toHaveLength(1)

    loads[0]!.resolve()
    await first
    await Promise.resolve()
    expect(loads).toHaveLength(2)
    loads[1]!.resolve()
    await second
    expect(loads).toHaveLength(2)
  })

  it('loads again after a load that failed', async () => {
    const loads: Array<ReturnType<typeof deferred>> = []
    const load = coalesced(() => {
      const next = deferred()
      loads.push(next)
      return next.promise
    })

    const first = load()
    const second = load()
    loads[0]!.reject(new Error('down'))
    await expect(first).rejects.toThrow('down')
    await Promise.resolve()
    await Promise.resolve()
    loads[1]!.resolve()
    await second

    expect(loads).toHaveLength(2)
  })
})
