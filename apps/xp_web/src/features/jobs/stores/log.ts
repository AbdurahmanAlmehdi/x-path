import { defineStore } from 'pinia'
import { computed, ref, shallowRef, triggerRef } from 'vue'

import type { JobState, LogLineFrame } from '@/api/client'
import { followJobLog } from '@/api/sockets'

/**
 * The log of the job the job page shows, live. Lines are only ever added,
 * each once: following again (after a resume, or a socket that dropped)
 * starts after the last line held.
 */
export const useJobLogStore = defineStore('jobLog', () => {
  const jobId = ref<string | null>(null)
  // A long log is many lines: the list is one reactive value, not one per line.
  const lines = shallowRef<LogLineFrame[]>([])
  /** The state the job was in when its log ended, if it did. */
  const ended = ref<JobState | null>(null)
  const following = ref(false)
  let stopFollowing: (() => void) | null = null

  /** The `seq` of the last line held. */
  const lastSeq = computed(() => lines.value.at(-1)?.seq ?? 0)

  /** Stops following the log. */
  function stop() {
    stopFollowing?.()
    stopFollowing = null
    following.value = false
  }

  /**
   * Follows the log of [id] from the line after the last one held: from the
   * start for another job.
   */
  function follow(id: string) {
    stop()
    if (jobId.value !== id) {
      jobId.value = id
      lines.value = []
    }
    ended.value = null
    following.value = true
    stopFollowing = followJobLog(id, lastSeq.value, {
      line(frame) {
        lines.value.push(frame)
        triggerRef(lines)
      },
      end(state) {
        ended.value = state
        following.value = false
        stopFollowing = null
      },
    })
  }

  return { jobId, lines, ended, following, lastSeq, follow, stop }
})
