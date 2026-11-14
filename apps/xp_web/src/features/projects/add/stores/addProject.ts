import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, doneOf, errorMessage, failureMessage, type Project } from '@/api/client'

/** Where a new project comes from: a git URL, or a folder on the engine's machine. */
export type ProjectSource = 'remote' | 'path'

/** Where adding a project stands. */
export type AddProjectStatus = 'idle' | 'adding' | 'review' | 'scanning' | 'discarded' | 'failed'

/**
 * Add project, then the review of its scan, as the Mac app does: keep it,
 * scan it again after a fix, or remove it. A folder whose `origin` is an
 * HTTPS URL on a host other than GitHub gets the SSH URL the engine offers,
 * for the person to confirm (ADR 0015).
 */
export const useAddProjectStore = defineStore('addProject', () => {
  const status = ref<AddProjectStatus>('idle')
  /** The project as its last scan saw it. */
  const project = ref<Project | null>(null)
  /** What the engine said when the last step failed. */
  const error = ref<string | null>(null)
  /** The SSH URL the engine offers instead of an HTTPS origin. */
  const sshUrl = ref<string | null>(null)

  /** Starts over. */
  function reset() {
    status.value = 'idle'
    project.value = null
    error.value = null
    sshUrl.value = null
  }

  /** Adds the repository at [location] (a URL or a folder) and scans it. */
  async function add(source: ProjectSource, location: string, confirmedSshUrl?: string): Promise<boolean> {
    const where = location.trim()
    const body = source === 'remote' ? { remote: where } : { path: where, sshUrl: confirmedSshUrl }
    status.value = 'adding'
    error.value = null
    sshUrl.value = null
    try {
      const { data, error: refusal, response } = await api.POST('/projects', { body })
      if (data) {
        project.value = data
        status.value = 'review'
        return true
      }
      const offered = (refusal as { sshUrl?: unknown } | undefined)?.sshUrl
      if (response.status === 422 && typeof offered === 'string') sshUrl.value = offered
      error.value = errorMessage(refusal, response.status)
    } catch (failure) {
      error.value = failureMessage(failure)
    }
    status.value = 'failed'
    return false
  }

  /** Scans the project just added again, after a fix in its repository. */
  async function rescan(): Promise<void> {
    const added = project.value
    if (!added) return
    status.value = 'scanning'
    error.value = null
    try {
      project.value = await dataOf(api.POST('/projects/{id}/scan', { params: { path: { id: added.id } } }))
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      status.value = 'review'
    }
  }

  /** Removes the project just added. */
  async function discard(): Promise<boolean> {
    const added = project.value
    if (!added) return false
    error.value = null
    try {
      await doneOf(api.DELETE('/projects/{id}', { params: { path: { id: added.id } } }))
      project.value = null
      status.value = 'discarded'
      return true
    } catch (failure) {
      error.value = failureMessage(failure)
      return false
    }
  }

  return { status, project, error, sshUrl, reset, add, rescan, discard }
})
