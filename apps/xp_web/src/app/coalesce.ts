/**
 * Wraps [load] so that a burst of calls loads at most twice: calls that come
 * while a load is under way wait for one more load after it, which then
 * sees everything they were for. A failed load does not stop the next one.
 */
export function coalesced(load: () => Promise<void>): () => Promise<void> {
  let running: Promise<void> | null = null
  let again: Promise<void> | null = null

  function start(): Promise<void> {
    running = load().finally(() => {
      running = null
    })
    return running
  }

  return () => {
    if (!running) return start()
    again ??= running
      .catch(() => {})
      .then(() => {
        again = null
        return start()
      })
    return again
  }
}
