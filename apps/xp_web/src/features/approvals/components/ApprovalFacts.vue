<script setup lang="ts">
import { computed } from 'vue'

import type { Approval, Job, Release } from '@/api/client'
import { useProjectsStore } from '@/features/projects/stores/projects'
import { pubspecLabel, stepKind } from '@/ui/format'

import { approvalConsequence, flavorOf, gateAction } from '../labels'

const props = defineProps<{
  approval: Approval
  job: Job | null
  release: Release | null
  /** Whether to say what approving does ("If you approve"). */
  consequence?: boolean
}>()

const projects = useProjectsStore()

const project = computed(() => projects.projects.find((each) => each.id === props.approval.projectId))
const app = computed(() => project.value?.profile.apps.find((each) => each.path === props.release?.app))
const flavor = computed(() => flavorOf(project.value, props.release))
const bundleId = computed(() => flavor.value?.iosBundleId ?? flavor.value?.androidAppId)

/** The step of the job that waits for this approval. */
const waiting = computed(() => props.job?.steps.find((step) => step.state === 'waitingForApproval'))

const projectLabel = computed(() =>
  [projects.nameOf(props.approval.projectId, { short: true }), app.value?.name]
    .filter(Boolean)
    .join(' · '),
)

const ifApproved = computed(() =>
  approvalConsequence(props.approval, {
    flavor: props.release?.flavor,
    bundleId: bundleId.value,
    baseBranch: props.release?.baseBranch ?? project.value?.defaultBaseBranch,
  }),
)
</script>

<template>
  <section class="panel">
    <dl class="facts">
      <dt>Project</dt>
      <dd>{{ projectLabel }}</dd>
      <template v-if="release">
        <dt>Flavor</dt>
        <dd>
          <strong>{{ release.flavor }}</strong>
          <span v-if="bundleId" class="mono muted"> · {{ bundleId }}</span>
        </dd>
      </template>
      <template v-if="approval.version">
        <dt>Version</dt>
        <dd class="mono">{{ pubspecLabel(approval.version) }}</dd>
      </template>
      <dt>Commit</dt>
      <dd class="mono">{{ approval.sha }}</dd>
      <template v-if="job">
        <dt>Job</dt>
        <dd>
          <RouterLink :to="{ name: 'job', params: { id: job.id } }">{{ job.name ?? job.id }}</RouterLink>
          <span v-if="waiting && approval.state === 'pending'" class="muted">
            · {{ stepKind(waiting.kind) }} waits for this
          </span>
        </dd>
      </template>
      <dt>Gate</dt>
      <dd class="muted">Project gate “{{ gateAction(approval.action) }}”</dd>
      <template v-if="approval.reason">
        <dt>Reason</dt>
        <dd>{{ approval.reason }}</dd>
      </template>
    </dl>
  </section>
  <section v-if="consequence" class="consequence" data-testid="consequence">
    <h3 class="xp-type-label muted">If you approve</h3>
    <p>{{ ifApproved }}</p>
    <p class="muted">If the commit, version or flavor change before then, this approval is void.</p>
  </section>
</template>

<style scoped>
.consequence h3 {
  margin: 0 0 var(--xp-space-4);
}

.consequence p {
  margin: 0 0 var(--xp-space-4);
}
</style>
