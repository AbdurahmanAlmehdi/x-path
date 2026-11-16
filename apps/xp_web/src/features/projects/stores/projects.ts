import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, type Project } from '@/api/client'
import { useLoad } from '@/api/requests'
import { followEvents } from '@/api/sockets'
import { shortName } from '@/ui/format'

/** The projects of the engine, oldest first, kept up to date by its events. */
export const useProjectsStore = defineStore('projects', () => {
  const projects = ref<Project[]>([])

  /** Asks the engine for the projects. */
  const { loaded, error, load } = useLoad(async () => {
    projects.value = (await dataOf(api.GET('/projects'))).projects
  })

  /** What the project [id] is called: its full name, or its last part when [short]; the id while unknown. */
  function nameOf(id: string, { short = false } = {}): string {
    const project = projects.value.find((each) => each.id === id)
    if (!project) return id
    return short ? shortName(project.fullName) : project.fullName
  }

  /** Loads again when a project is added, scanned, edited or removed. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync' || item.event.type.startsWith('project.')) void load()
    })
  }

  return { projects, loaded, error, load, nameOf, follow }
})
