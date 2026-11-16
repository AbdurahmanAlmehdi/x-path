import { describe, expect, it } from 'vitest'

import { ApiFailure } from './client'
import { useCommand, useLoad } from './requests'

const refused = new ApiFailure('No such token.', 404, 'not_found')
const unanswered = 'The engine did not answer. Check that it is running.'

describe('useLoad', () => {
  it('reads, then says it loaded without an error', async () => {
    let reads = 0
    const { loaded, error, load } = useLoad(async () => {
      reads++
    })

    expect(loaded.value).toBe(false)
    await load()

    expect(reads).toBe(1)
    expect(loaded.value).toBe(true)
    expect(error.value).toBeNull()
  })

  it('says why a read failed, and forgets it once one works', async () => {
    let failure: unknown = refused
    const { loaded, error, load } = useLoad(async () => {
      if (failure) throw failure
    })

    await load()
    expect(loaded.value).toBe(true)
    expect(error.value).toBe('No such token.')

    failure = new TypeError('fetch failed')
    await load()
    expect(error.value).toBe(unanswered)

    failure = null
    await load()
    expect(error.value).toBeNull()
  })

  it('reads at most twice for a burst of calls', async () => {
    let reads = 0
    let finish!: () => void
    const { load } = useLoad(() => {
      reads++
      return new Promise<void>((resolve) => (finish = resolve))
    })

    const first = load()
    const again = load()
    load()
    finish()
    await first
    await Promise.resolve()
    finish()
    await again

    expect(reads).toBe(2)
  })
})

describe('useCommand', () => {
  it('is idle until a command is sent', () => {
    expect(useCommand<string | null>(null).busy.value).toBeNull()
    expect(useCommand(false).busy.value).toBe(false)
  })

  it('is busy with the command on its way, and answers what it answered', async () => {
    const command = useCommand<'saving' | null>(null)
    let busyDuring: 'saving' | null = null

    const answer = await command.run('saving', async () => {
      busyDuring = command.busy.value
      return 42
    })

    expect(busyDuring).toBe('saving')
    expect(answer).toBe(42)
    expect(command.busy.value).toBeNull()
    expect(command.error.value).toBeNull()
  })

  it('answers null with the refusal, idle again', async () => {
    const command = useCommand(false)

    const answer = await command.run(true, () => Promise.reject(refused))

    expect(answer).toBeNull()
    expect(command.error.value).toBe('No such token.')
    expect(command.busy.value).toBe(false)
  })

  it('says the engine did not answer when the call never reached it', async () => {
    const command = useCommand<string | null>(null)

    await command.run('tok_1', () => Promise.reject(new TypeError('fetch failed')))

    expect(command.error.value).toBe(unanswered)
  })

  it('forgets the last refusal when the next command is sent, or on dismiss', async () => {
    const command = useCommand<string | null>(null)

    await command.run('a', () => Promise.reject(refused))
    const sending = command.run('b', () => Promise.resolve(true))
    expect(command.error.value).toBeNull()
    await sending

    await command.run('c', () => Promise.reject(refused))
    command.dismiss()
    expect(command.error.value).toBeNull()
  })
})
