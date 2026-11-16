import { ref, shallowRef } from 'vue'

import { coalesced } from '@/app/coalesce'

import { failureMessage } from './client'

/**
 * What a page reads from the engine as a whole, such as a list: [load]
 * runs [read] (a burst of calls reads at most twice), [error] says why the
 * last read failed, and [loaded] that one ended, either way.
 */
export function useLoad(read: () => Promise<void>) {
  const loaded = ref(false)
  const error = ref<string | null>(null)

  const load = coalesced(async () => {
    try {
      await read()
      error.value = null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  return { loaded, error, load }
}

/**
 * Commands a page sends to the engine: [busy] is the one on its way,
 * [idle] while none is, and [error] what the engine said when it refused
 * the last one.
 */
export function useCommand<K>(idle: K) {
  const busy = shallowRef<K>(idle)
  const error = ref<string | null>(null)

  /** Runs [send] as [key]: what it answers, or `null` with [error] saying why not. */
  async function run<T>(key: K, send: () => Promise<T>): Promise<T | null> {
    busy.value = key
    error.value = null
    try {
      return await send()
    } catch (failure) {
      error.value = failureMessage(failure)
      return null
    } finally {
      busy.value = idle
    }
  }

  /** Forgets the last refusal. */
  function dismiss() {
    error.value = null
  }

  return { busy, error, run, dismiss }
}
