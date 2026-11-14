import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { FakeSocket, stubSockets } from '@/testing/sockets'

import { useJobLogStore } from './log'

const line = (seq: number) => ({
  type: 'line',
  seq,
  step: 0,
  at: '2026-11-14T09:00:00Z',
  stream: 'stdout',
  text: `line ${seq}`,
})

describe('useJobLogStore', () => {
  let store: ReturnType<typeof useJobLogStore>

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
    store = useJobLogStore()
  })
  afterEach(() => store.stop())

  it('follows the log from its start, line by line', () => {
    store.follow('job_2')
    FakeSocket.last().open().send(line(1)).send(line(2))

    expect(FakeSocket.last().path).toBe('/api/v1/jobs/job_2/logs?after=0')
    expect(store.lines.map((each) => each.seq)).toEqual([1, 2])
    expect(store.lastSeq).toBe(2)
    expect(store.following).toBe(true)
  })

  it('knows when the log ended, and follows on from the last line after a resume', () => {
    store.follow('job_2')
    FakeSocket.last().open().send(line(1)).send({ type: 'end', state: 'interrupted' })
    expect(store.ended).toBe('interrupted')
    expect(store.following).toBe(false)

    store.follow('job_2')

    expect(store.ended).toBeNull()
    expect(FakeSocket.last().path).toBe('/api/v1/jobs/job_2/logs?after=1')
    expect(store.lines).toHaveLength(1)
  })

  it('starts over for another job, and stops the socket of the one before', () => {
    store.follow('job_2')
    const first = FakeSocket.last().open().send(line(1))

    store.follow('job_3')

    expect(first.closedWith).toBe(1000)
    expect(store.lines).toEqual([])
    expect(FakeSocket.last().path).toBe('/api/v1/jobs/job_3/logs?after=0')
  })

  it('stops', () => {
    store.follow('job_2')
    const socket = FakeSocket.last()

    store.stop()

    expect(socket.closedWith).toBe(1000)
    expect(store.following).toBe(false)
  })
})
