import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, type WorkflowSummary } from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'

/**
 * The workflows of the projects the app has shown, for their names: a run
 * names its workflow by id. Each project's list is asked for once, and
 * again when its workflows change while the app [follow]s.
 */
export const useWorkflowsStore = defineStore('workflows', () => {
  const byProject = ref<Record<string, WorkflowSummary[]>>({})
  const asked = new Map<string, Promise<WorkflowSummary[]>>()

  /** The workflows of [projectId], from the engine the first time. */
  function ofProject(projectId: string): Promise<WorkflowSummary[]> {
    let workflows = asked.get(projectId)
    if (!workflows) {
      workflows = dataOf(
        api.GET('/projects/{id}/workflows', { params: { path: { id: projectId } } }),
      ).then(({ workflows }) => {
        byProject.value[projectId] = workflows
        return workflows
      })
      workflows.catch(() => asked.delete(projectId))
      asked.set(projectId, workflows)
    }
    return workflows
  }

  /** Asks for the workflows of every project in [projectIds] not known yet; failures leave ids. */
  async function know(projectIds: Iterable<string>): Promise<void> {
    await Promise.allSettled([...new Set(projectIds)].map(ofProject))
  }

  /** What the workflow [id] is called: its title, else its name, else its id. */
  function name(id: string): string {
    for (const workflows of Object.values(byProject.value)) {
      const workflow = workflows.find((each) => each.id === id)
      if (workflow) return workflow.title ?? workflow.name
    }
    return id
  }

  /** Asks again for the workflows of [projectIds], which may have changed. */
  function refresh(projectIds: string[]): Promise<void> {
    for (const projectId of projectIds) asked.delete(projectId)
    return know(projectIds)
  }

  /** Keeps the names up to date with the engine's events. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync') {
        void refresh(Object.keys(byProject.value))
      } else if (item.event.type.startsWith('workflow.')) {
        const projectId = payloadValue(item.event, 'projectId')
        if (projectId) void refresh([projectId])
      }
    })
  }

  return { byProject, ofProject, know, name, follow }
})
