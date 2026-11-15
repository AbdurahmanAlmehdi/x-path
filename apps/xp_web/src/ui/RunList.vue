<script setup lang="ts">
import type { Run } from '@/api/client'

import { formatTime, originOf, scopeOf, timeAgo, versionLabel } from './format'
import StatusBadge from './StatusBadge.vue'

/** A list of runs, for the Runs pages and a project's recent runs; the page names what they ran. */
defineProps<{
  runs: Run[]
  /** What to say when there is no run. */
  empty: string
  /** What the workflow of an id is called. */
  workflowName: (id: string) => string
  /** What the project of an id is called, when each run names its project: the list holds several. */
  projectName?: (id: string) => string
}>()
</script>

<template>
  <p v-if="runs.length === 0" class="muted empty">{{ empty }}</p>
  <ul v-else class="runs">
    <li v-for="run in runs" :key="run.id">
      <RouterLink :to="{ name: 'run', params: { id: run.id } }" class="run" :data-run="run.id">
        <StatusBadge :state="run.state" />
        <span class="what">
          <span class="xp-type-body-strong workflow">{{ workflowName(run.workflowId) }}</span>
          <span v-if="projectName" class="muted project">{{ projectName(run.projectId) }}</span>
        </span>
        <span v-if="scopeOf(run)" class="mono muted">{{ scopeOf(run) }}</span>
        <span v-if="run.version" class="mono">{{ versionLabel(run.version, run.build) }}</span>
        <span v-if="originOf(run)" class="muted origin">{{ originOf(run) }}</span>
        <time class="xp-type-caption muted" :datetime="run.createdAt" :title="formatTime(run.createdAt)">
          {{ timeAgo(run.createdAt) }}
        </time>
      </RouterLink>
    </li>
  </ul>
</template>

<style scoped>
.empty {
  padding: var(--xp-space-12) 0;
}

.runs {
  list-style: none;
  margin: 0;
  padding: 0;
}

.runs li + li {
  border-top: var(--xp-border-width-hairline) solid var(--xp-color-border-subtle);
}

.run {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-4) var(--xp-space-12);
  min-height: var(--xp-size-row-default);
  padding: var(--xp-space-6) var(--xp-space-8);
  color: var(--xp-color-text-primary);
  text-decoration: none;
  border-radius: var(--xp-radius-md);
}

.run:hover {
  background: var(--xp-color-surface-hover);
}

.what {
  display: flex;
  flex: 1 1 200px;
  flex-direction: column;
  min-width: 0;
}

.workflow,
.project {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

time {
  margin-left: auto;
  white-space: nowrap;
}
</style>
