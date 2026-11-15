import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, ApiFailure, dataOf, failureMessage, type Project, type Run } from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/** How many runs the overview shows. */
export const recentRunCount = 10

/**
 * The project the overview shows: its profile, and its newest runs, kept
 * up to date by the engine's events.
 */
export const useProjectStore = defineStore('project', () => {
  const id = ref<string | null>(null)
  const project = ref<Project | null>(null)
  const runs = ref<Run[]>([])
  /** Whether the engine has no such project (any more). */
  const missing = ref(false)
  const error = ref<string | null>(null)

  /** How many of the runs shown are under way. */
  const running = computed(() => runs.value.filter((run) => run.state === 'running').length)

  async function loadProject(projectId: string) {
    try {
      const found = await dataOf(api.GET('/projects/{id}', { params: { path: { id: projectId } } }))
      if (id.value !== projectId) return
      project.value = found
      missing.value = false
      error.value = null
    } catch (failure) {
      if (id.value !== projectId) return
      missing.value = failure instanceof ApiFailure && failure.status === 404
      error.value = missing.value ? null : failureMessage(failure)
    }
  }

  async function loadRuns(projectId: string) {
    try {
      const page = await dataOf(
        api.GET('/projects/{id}/runs', {
          params: { path: { id: projectId }, query: { limit: recentRunCount } },
        }),
      )
      if (id.value === projectId) runs.value = page.runs
    } catch {
      // The project's own answer says what is wrong.
    }
  }

  const refreshProject = coalesced(() => (id.value ? loadProject(id.value) : Promise.resolve()))
  const refreshRuns = coalesced(() => (id.value ? loadRuns(id.value) : Promise.resolve()))

  /** Shows the project [projectId]. */
  async function open(projectId: string): Promise<void> {
    if (id.value !== projectId) {
      id.value = projectId
      project.value = null
      runs.value = []
      missing.value = false
      error.value = null
    }
    await Promise.all([loadProject(projectId), loadRuns(projectId)])
  }

  /** Follows the events of the project. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync') {
        void refreshProject()
        void refreshRuns()
        return
      }
      const { type } = item.event
      if (payloadValue(item.event, 'projectId') !== id.value) return
      if (type.startsWith('project.')) void refreshProject()
      if (type === 'run.dispatched' || type === 'job.state_changed') void refreshRuns()
    })
  }

  return { id, project, runs, missing, error, running, open, follow }
})
