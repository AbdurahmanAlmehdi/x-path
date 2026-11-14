import {
  createRouter,
  createWebHistory,
  type RouteLocationNormalized,
  type Router,
  type RouterHistory,
} from 'vue-router'

import { onSignedOut } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'

import { safeNext } from './next'

declare module 'vue-router' {
  interface RouteMeta {
    /** Pages anyone may see, signed in or not. */
    public?: boolean
  }
}

/** The sign-in page, with where to go back to. */
export function signInRoute(to: Pick<RouteLocationNormalized, 'fullPath'>) {
  return to.fullPath === '/'
    ? { name: 'sign-in' }
    : { name: 'sign-in', query: { next: to.fullPath } }
}

/**
 * The app's routes. Every page but sign-in needs a session: a signed-out
 * visit goes to `/sign-in?next=<path>`, and back there after sign-in. The
 * screens of later phases go under the shell.
 */
export function createAppRouter(history: RouterHistory = createWebHistory()): Router {
  const router = createRouter({
    history,
    routes: [
      {
        path: '/sign-in',
        name: 'sign-in',
        component: () => import('@/features/session/views/SignInView.vue'),
        meta: { public: true },
      },
      {
        path: '/',
        component: () => import('@/ui/AppShell.vue'),
        children: [
          {
            path: '',
            name: 'home',
            component: () => import('@/ui/HomeView.vue'),
          },
          {
            path: 'projects',
            name: 'projects',
            component: () => import('@/features/projects/views/ProjectsView.vue'),
          },
          {
            path: 'projects/:id',
            name: 'project',
            component: () => import('@/features/projects/views/ProjectView.vue'),
          },
          {
            path: 'projects/:id/runs',
            name: 'project-runs',
            component: () => import('@/features/runs/views/RunsView.vue'),
          },
          {
            path: 'projects/:id/dispatch',
            name: 'dispatch',
            component: () => import('@/features/dispatch/views/DispatchView.vue'),
          },
          {
            path: 'runs',
            name: 'runs',
            component: () => import('@/features/runs/views/RunsView.vue'),
          },
          {
            path: 'runs/:id',
            name: 'run',
            component: () => import('@/features/runs/views/RunView.vue'),
          },
          {
            path: 'jobs/:id',
            name: 'job',
            component: () => import('@/features/jobs/views/JobView.vue'),
          },
          {
            path: ':pathMatch(.*)*',
            name: 'not-found',
            component: () => import('@/ui/NotFoundView.vue'),
          },
        ],
      },
    ],
  })

  router.beforeEach(async (to) => {
    const session = useSessionStore()
    try {
      await session.load()
    } catch {
      // The engine did not answer: the session stays unknown, and only the
      // sign-in page opens, where signing in tells what is wrong.
    }
    if (to.name === 'sign-in' && session.status === 'signedIn') {
      return safeNext(to.query.next)
    }
    if (to.meta.public || session.status === 'signedIn') return true
    return signInRoute(to)
  })

  return router
}

/**
 * When the engine ends the session (signed out elsewhere, revoked,
 * expired), forgets it and goes to sign-in, and back to this page after it
 * (D12). Returns the function that stops following.
 */
export function followSessionEnd(router: Router): () => void {
  return onSignedOut(() => {
    useSessionStore().signedOut()
    const current = router.currentRoute.value
    if (current.matched.length > 0 && !current.meta.public) {
      void router.replace(signInRoute(current))
    }
  })
}
