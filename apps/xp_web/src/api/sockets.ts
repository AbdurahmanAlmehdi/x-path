import {
  apiBase,
  sessionEnded,
  type JobState,
  type LogFrame,
  type LogLineFrame,
  type SequencedEvent,
} from './client'

/** The engine closes a socket with this code when its session ends (D12). */
export const sessionEndedCloseCode = 4401

/** The engine closes `/events` with this code when it cannot resume it. */
export const resyncCloseCode = 4409

/** How long a feed waits before it reconnects: doubling up to `max`. */
export const reconnectDelay = { initial: 1000, max: 30_000 }

/**
 * The WebSocket address of [path] under the API, on the page's own origin:
 * the session cookie goes with it, and the engine checks the `Origin`
 * (ADR 0018, D2).
 */
export function socketUrl(path: string, query: Record<string, number | undefined> = {}): string {
  const url = new URL(`${apiBase}${path}`, window.location.href)
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
  for (const [name, value] of Object.entries(query)) {
    if (value !== undefined) url.searchParams.set(name, String(value))
  }
  return url.href
}

/** What a feed does after it handled one frame. */
type Next = 'read' | 'reconnect' | 'finish'

interface Feed {
  /** The address to open, resuming from the feed's cursor. */
  url(): string
  /** Handles one frame. */
  frame(data: unknown): Next
  /** The socket closed before it opened: the engine refused the upgrade. */
  refused?(): void
  /** The engine closed the socket with [code]: whether to reconnect at once. */
  closed?(code: number): boolean
}

/**
 * Keeps a socket of [feed] open: reconnects when it drops, after a delay
 * that doubles while connections keep failing, until the feed finishes or
 * the returned function stops it. A close with 4401 ends the session and
 * never reconnects. Mirrors `SocketFeed` of `xp_client`.
 */
function keepOpen(feed: Feed): () => void {
  let stopped = false
  let socket: WebSocket | null = null
  let timer: ReturnType<typeof setTimeout> | undefined
  let failures = 0

  function leave(current: WebSocket) {
    current.onopen = current.onmessage = current.onclose = null
    current.close(1000)
    socket = null
  }

  function later() {
    failures += 1
    const delay = Math.min(reconnectDelay.initial * 2 ** (failures - 1), reconnectDelay.max)
    timer = setTimeout(connect, delay)
  }

  function connect() {
    timer = undefined
    if (stopped) return
    const current = new WebSocket(feed.url())
    let opened = false
    socket = current
    current.onopen = () => {
      opened = true
    }
    current.onmessage = (message: MessageEvent) => {
      let next: Next
      try {
        next = feed.frame(JSON.parse(String(message.data)))
      } catch {
        // A frame this app cannot read, for example one of a newer engine.
        return
      }
      failures = 0
      if (next === 'read') return
      leave(current)
      if (next === 'finish') stopped = true
      else connect()
    }
    current.onclose = (event: CloseEvent) => {
      socket = null
      if (event.code === sessionEndedCloseCode) {
        stopped = true
        sessionEnded()
        return
      }
      if (!opened) feed.refused?.()
      if (opened && feed.closed?.(event.code)) connect()
      else later()
    }
  }

  connect()
  return () => {
    stopped = true
    clearTimeout(timer)
    if (socket) leave(socket)
  }
}

/** What the event feed tells its listeners. */
export type EventItem =
  | { kind: 'event'; event: SequencedEvent }
  /**
   * The engine could not resume the feed (it keeps a window of events, or
   * it restarted): what a listener holds may be out of date, so it loads
   * it again.
   */
  | { kind: 'resync' }

type EventListener = (item: EventItem) => void

const eventListeners = new Set<EventListener>()
let stopEvents: (() => void) | null = null

/**
 * Follows the engine's events (`/events`): one socket per tab, open while
 * someone listens, resumed with `after=<seq>` so no event is missed or
 * handled twice. Returns the function that stops [listener].
 */
export function followEvents(listener: EventListener): () => void {
  eventListeners.add(listener)
  stopEvents ??= openEvents()
  return () => {
    eventListeners.delete(listener)
    if (eventListeners.size > 0) return
    stopEvents?.()
    stopEvents = null
  }
}

function openEvents(): () => void {
  let cursor: number | undefined
  const emit = (item: EventItem) => eventListeners.forEach((listener) => listener(item))
  const resync = () => {
    cursor = undefined
    emit({ kind: 'resync' })
  }
  return keepOpen({
    url: () => socketUrl('/events', { after: cursor }),
    frame(data) {
      const event = data as SequencedEvent
      if (event.type === 'stream.opened') {
        // Its `seq` is the head of the log: only a feed without a cursor
        // starts from there.
        cursor ??= event.seq
        return 'read'
      }
      if (cursor !== undefined && event.seq <= cursor) return 'read'
      cursor = event.seq
      emit({ kind: 'event', event })
      return 'read'
    },
    refused() {
      // A browser cannot read why: a cursor the engine no longer holds
      // (`409`) is the case to recover from.
      if (cursor !== undefined) resync()
    },
    closed(code) {
      if (code !== resyncCloseCode) return false
      resync()
      return true
    },
  })
}

/** What the log of a job tells its follower. */
export interface LogFollower {
  /** A line, each once and in order. */
  line(frame: LogLineFrame): void
  /** The log ended: the job is not running, in [state]. */
  end(state: JobState): void
}

/**
 * Follows the log of the job [jobId] after the line [after], resumed from
 * the last line handled when the socket drops or the engine skips lines
 * for a slow reader (`gap`), so a line is never shown twice or missed.
 * Returns the function that stops it.
 */
export function followJobLog(jobId: string, after: number, follower: LogFollower): () => void {
  let cursor = after
  return keepOpen({
    url: () => socketUrl(`/jobs/${encodeURIComponent(jobId)}/logs`, { after: cursor }),
    frame(data) {
      const frame = data as LogFrame
      switch (frame.type) {
        case 'line':
          if (frame.seq > cursor) {
            cursor = frame.seq
            follower.line(frame)
          }
          return 'read'
        case 'gap':
          return 'reconnect'
        case 'end':
          follower.end(frame.state)
          return 'finish'
      }
      return 'read'
    },
  })
}

/** The string [key] of the payload of [event], if it has one. */
export function payloadValue(event: SequencedEvent, key: string): string | undefined {
  const value = (event.payload as Record<string, unknown>)[key]
  return typeof value === 'string' ? value : undefined
}
