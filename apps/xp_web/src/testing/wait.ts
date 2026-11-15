import { vi } from 'vitest'

/**
 * How long a test waits for a condition. Long enough for a lazy page's
 * first import under coverage and parallel workers, and well under the
 * test timeout (`vitest.config.ts`), so a wait that fails says what it
 * waited for instead of a bare timeout.
 */
export const waitBudget = 5000

/** Retries [check] (an `expect`, or a function that throws) until it passes, within [waitBudget]. */
export function eventually<T>(check: () => T | Promise<T>): Promise<T> {
  return vi.waitFor(check, { timeout: waitBudget, interval: 20 })
}
