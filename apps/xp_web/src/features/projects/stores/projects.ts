import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, failureMessage, type Project } from '@/api/client'
import { followEvents } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/** The projects of the engine, oldest first, kept up to date by its events. */
export const useProjectsStore = defineStore('projects', () => {
  const projects = ref<Project[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)

  /** Asks the engine for the projects. */
  const load = coalesced(async () => {
    try {
      projects.value = (await dataOf(api.GET('/projects'))).projects
      error.value = null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  /** Loads again when a project is added, scanned, edited or removed. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync' || item.event.type.startsWith('project.')) void load()
    })
  }

  return { projects, loaded, error, load, follow }
})
