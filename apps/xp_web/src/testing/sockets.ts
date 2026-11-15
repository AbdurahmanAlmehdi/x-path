import { vi } from 'vitest'

/**
 * A WebSocket the test drives: it records the sockets the app opens, and
 * the test opens them, sends frames and closes them as the engine would.
 */
export class FakeSocket {
  static opened: FakeSocket[] = []

  onopen: (() => void) | null = null
  onmessage: ((message: { data: string }) => void) | null = null
  onclose: ((event: { code: number }) => void) | null = null
  closedWith: number | null = null

  constructor(readonly url: string) {
    FakeSocket.opened.push(this)
  }

  /** The address the app opened, without the origin. */
  get path(): string {
    const url = new URL(this.url)
    return `${url.pathname}${url.search}`
  }

  /** The app closes it. */
  close(code: number) {
    this.closedWith = code
  }

  /** The engine accepts the upgrade. */
  open() {
    this.onopen?.()
    return this
  }

  /** The engine sends [frame], as JSON unless it is a string. */
  send(frame: unknown) {
    this.onmessage?.({ data: typeof frame === 'string' ? frame : JSON.stringify(frame) })
    return this
  }

  /** The engine (or the network) closes it with [code]. */
  drop(code = 1006) {
    this.onclose?.({ code })
  }

  /** The newest socket the app opened. */
  static last(): FakeSocket {
    const socket = FakeSocket.opened.at(-1)
    if (!socket) throw new Error('No socket was opened.')
    return socket
  }
}

/** Replaces `WebSocket` with [FakeSocket]; returns the sockets opened. */
export function stubSockets(): FakeSocket[] {
  FakeSocket.opened = []
  vi.stubGlobal('WebSocket', FakeSocket)
  return FakeSocket.opened
}

/** An event of the engine, as `/events` sends it. */
export function eventOf(seq: number, type: string, payload: Record<string, unknown> = {}) {
  return { seq, at: '2026-11-14T09:00:00Z', type, payload }
}

/** The event feed the app opened, as the engine opens it, and how to talk on it. */
export function openEventFeed() {
  const socket = [...FakeSocket.opened].reverse().find((each) => each.path.startsWith('/api/v1/events'))
  if (!socket) throw new Error('The app follows no events.')
  socket.open().send(eventOf(0, 'stream.opened'))
  let seq = 0
  return {
    /** The engine sends the event [type]. */
    send(type: string, payload: Record<string, unknown> = {}) {
      socket.send(eventOf(++seq, type, payload))
    },
    /** The engine can no longer resume the feed: listeners reload. */
    resync() {
      socket.drop(4409)
    },
  }
}
