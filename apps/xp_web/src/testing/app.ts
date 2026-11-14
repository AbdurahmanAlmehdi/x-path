import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { vi } from 'vitest'
import { createMemoryHistory, type Router } from 'vue-router'

import App from '@/app/App.vue'
import { createAppRouter } from '@/app/router'

/** The app, mounted at [path] with an active Pinia, and its router. */
export async function openApp(path: string): Promise<{ app: VueWrapper; router: Router }> {
  const router = createAppRouter(createMemoryHistory())
  await router.push(path)
  const app = mount(App, { global: { plugins: [router] } })
  await flushPromises()
  // A lazy page arrives after the navigation; the first import of one
  // compiles it.
  await vi.waitFor(
    () => {
      if (app.find('main section').exists() === false) throw new Error('No page yet.')
    },
    { timeout: 5000 },
  )
  await flushPromises()
  return { app, router }
}
