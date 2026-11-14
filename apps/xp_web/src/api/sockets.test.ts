import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { eventOf, FakeSocket, stubSockets } from '@/testing/sockets'

import { onSignedOut } from './client'
import {
  type EventItem,
  followEvents,
  followJobLog,
  payloadValue,
  reconnectDelay,
  resyncCloseCode,
  sessionEndedCloseCode,
  socketUrl,
} from './sockets'

const line = (seq: number, text = `line ${seq}`) => ({
  type: 'line',
  seq,
  step: 0,
  at: '2026-11-14T09:00:00Z',
  stream: 'stdout',
  text,
})

describe('socketUrl', () => {
  afterEach(() => window.history.replaceState(null, '', '/'))

  it('is the API path on the page origin, as ws', () => {
    expect(socketUrl('/events')).toBe(`ws://${window.location.host}/api/v1/events`)
  })

  it('adds the query values that are set', () => {
    expect(socketUrl('/events', { after: 7, before: undefined })).toBe(
      `ws://${window.location.host}/api/v1/events?after=7`,
    )
  })
})

describe('sockets', () => {
  let sockets: FakeSocket[]
  const stops: Array<() => void> = []

  beforeEach(() => {
    vi.useFakeTimers()
    sockets = stubSockets()
  })

  afterEach(() => {
    stops.splice(0).forEach((stop) => stop())
    vi.useRealTimers()
  })

  describe('followEvents', () => {
    function follow() {
      const items: EventItem[] = []
      stops.push(followEvents((item) => items.push(item)))
      return items
    }

    it('opens one socket for every listener, and closes it after the last', () => {
      const first = followEvents(() => {})
      const second = followEvents(() => {})

      expect(sockets).toHaveLength(1)
      expect(sockets[0]?.path).toBe('/api/v1/events')

      first()
      expect(sockets[0]?.closedWith).toBeNull()
      second()
      expect(sockets[0]?.closedWith).toBe(1000)
    })

    it('passes on events, not the opening frame, and skips what it has seen', () => {
      const items = follow()
      const socket = FakeSocket.last().open()

      socket.send(eventOf(4, 'stream.opened'))
      socket.send(eventOf(5, 'run.dispatched', { projectId: 'prj_1' }))
      socket.send(eventOf(5, 'run.dispatched', { projectId: 'prj_1' }))
      socket.send('not json')

      expect(items).toEqual([
        { kind: 'event', event: eventOf(5, 'run.dispatched', { projectId: 'prj_1' }) },
      ])
    })

    it('reconnects after the last event it handled, later and later', () => {
      follow()
      FakeSocket.last().open().send(eventOf(4, 'stream.opened')).send(eventOf(6, 'x')).drop()

      vi.advanceTimersByTime(reconnectDelay.initial)
      expect(FakeSocket.last().path).toBe('/api/v1/events?after=6')

      FakeSocket.last().open().drop(1000)
      vi.advanceTimersByTime(reconnectDelay.initial)
      expect(sockets).toHaveLength(2)
      vi.advanceTimersByTime(reconnectDelay.initial)
      expect(sockets).toHaveLength(3)
    })

    it('waits at most the longest delay', () => {
      follow()
      for (let i = 0; i < 10; i++) {
        FakeSocket.last().open().drop()
        vi.advanceTimersByTime(reconnectDelay.max)
      }

      expect(sockets).toHaveLength(11)
    })

    it('starts over and asks for a reload when the engine closes with 4409', () => {
      const items = follow()
      FakeSocket.last().open().send(eventOf(4, 'stream.opened')).drop(resyncCloseCode)

      expect(items).toEqual([{ kind: 'resync' }])
      expect(sockets).toHaveLength(2)
      expect(FakeSocket.last().path).toBe('/api/v1/events')
    })

    it('starts over and asks for a reload when a resume is refused', () => {
      const items = follow()
      FakeSocket.last().open().send(eventOf(4, 'stream.opened')).drop()
      vi.advanceTimersByTime(reconnectDelay.initial)

      FakeSocket.last().drop()
      vi.advanceTimersByTime(reconnectDelay.initial * 2)

      expect(items).toEqual([{ kind: 'resync' }])
      expect(FakeSocket.last().path).toBe('/api/v1/events')
    })

    it('retries a first connection without asking for a reload', () => {
      const items = follow()
      FakeSocket.last().drop()
      vi.advanceTimersByTime(reconnectDelay.initial)

      expect(items).toEqual([])
      expect(sockets).toHaveLength(2)
    })

    it('ends the session on 4401 and does not reconnect', () => {
      const ended = vi.fn()
      stops.push(onSignedOut(ended))
      follow()

      FakeSocket.last().open().drop(sessionEndedCloseCode)
      vi.advanceTimersByTime(reconnectDelay.max)

      expect(ended).toHaveBeenCalledOnce()
      expect(sockets).toHaveLength(1)
    })

    it('stops a reconnect that is waiting', () => {
      const stop = followEvents(() => {})
      FakeSocket.last().drop()

      stop()
      vi.advanceTimersByTime(reconnectDelay.max)

      expect(sockets).toHaveLength(1)
    })
  })

  describe('followJobLog', () => {
    function follow(after = 0) {
      const lines: number[] = []
      const ends: string[] = []
      stops.push(
        followJobLog('job 1', after, {
          line: (frame) => lines.push(frame.seq),
          end: (state) => ends.push(state),
        }),
      )
      return { lines, ends }
    }

    it('reads the log after the line given', () => {
      follow(3)

      expect(FakeSocket.last().path).toBe('/api/v1/jobs/job%201/logs?after=3')
    })

    it('passes on each line once, and resumes after the last one when it drops', () => {
      const { lines } = follow()
      FakeSocket.last().open().send(line(1)).send(line(2)).send(line(2)).drop()

      vi.advanceTimersByTime(reconnectDelay.initial)
      FakeSocket.last().open().send(line(2)).send(line(3))

      expect(lines).toEqual([1, 2, 3])
      expect(FakeSocket.last().path).toBe('/api/v1/jobs/job%201/logs?after=2')
    })

    it('reconnects at once over a gap, from the last line it has', () => {
      const { lines } = follow()
      const first = FakeSocket.last().open().send(line(1))

      first.send({ type: 'gap', fromSeq: 2, toSeq: 9, count: 8 })

      expect(first.closedWith).toBe(1000)
      expect(FakeSocket.last().path).toBe('/api/v1/jobs/job%201/logs?after=1')
      expect(lines).toEqual([1])
    })

    it('ends with the state of the job, and stays closed', () => {
      const { ends } = follow()
      const socket = FakeSocket.last().open().send({ type: 'end', state: 'succeeded' })

      vi.advanceTimersByTime(reconnectDelay.max)

      expect(ends).toEqual(['succeeded'])
      expect(socket.closedWith).toBe(1000)
      expect(sockets).toHaveLength(1)
    })

    it('ignores frames it does not know', () => {
      const { lines, ends } = follow()

      FakeSocket.last().open().send({ type: 'later' })

      expect([...lines, ...ends]).toEqual([])
    })
  })
})

describe('payloadValue', () => {
  it('is a string of the payload, and nothing else', () => {
    const event = eventOf(1, 'job.state_changed', { jobId: 'job_1', count: 2 }) as never

    expect(payloadValue(event, 'jobId')).toBe('job_1')
    expect(payloadValue(event, 'count')).toBeUndefined()
    expect(payloadValue(event, 'missing')).toBeUndefined()
  })
})
