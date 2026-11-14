<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { useProjectsStore } from '@/features/projects/stores/projects'
import Badge from '@/ui/Badge.vue'
import { useFollowing } from '@/ui/following'
import { formatCountdown, formatTime, shortSha } from '@/ui/format'

import ApprovalDetail from '../components/ApprovalDetail.vue'
import { approvalStatus, approvalTitle, expiresSoon, gateAction } from '../labels'
import { type ApprovalsFilter, approvalsFilters, useApprovalsStore } from '../stores/approvals'

const route = useRoute()
const router = useRouter()
const store = useApprovalsStore()
const projects = useProjectsStore()

const filterLabels: Record<ApprovalsFilter, string> = {
  pending: 'Pending',
  decided: 'Decided',
  expired: 'Expired',
}

watch(
  () => (route.params.id ? String(route.params.id) : null),
  (id) => store.select(id),
  { immediate: true },
)
void store.load()
void projects.load()
useFollowing(store.follow, projects.follow)

function projectName(projectId: string): string {
  return projects.projects.find((each) => each.id === projectId)?.fullName.split('/').at(-1) ?? projectId
}

const empty = computed(() => (store.filter === 'pending' ? 'Nothing is waiting' : 'Nothing here'))

async function show(filter: ApprovalsFilter) {
  store.show(filter)
  if (route.params.id) await router.push({ name: 'approvals' })
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Approvals</h1>
        <p class="muted" data-testid="pending-count">{{ store.pendingCount }} pending</p>
      </div>
      <div class="actions filters" role="group" aria-label="Show">
        <button
          v-for="filter in approvalsFilters"
          :key="filter"
          type="button"
          :aria-pressed="store.filter === filter"
          :class="{ selected: store.filter === filter }"
          @click="show(filter)"
        >
          {{ filterLabels[filter] }}
        </button>
      </div>
    </header>

    <div class="inbox">
      <div class="list">
        <h2 class="xp-type-label muted">{{ filterLabels[store.filter] }} · {{ store.visible.length }}</h2>
        <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
        <p v-else-if="!store.loaded" class="muted">Loading…</p>
        <ul>
          <li v-for="approval in store.visible" :key="approval.id">
            <RouterLink
              :to="{ name: 'approvals', params: { id: approval.id } }"
              class="row"
              :class="{ selected: approval.id === store.selected?.id }"
            >
              <span class="row-title">
                <Badge :status="approvalStatus(approval.state)" />
                <span class="xp-type-body-strong">{{ approvalTitle(approval) }}</span>
              </span>
              <span class="muted meta">
                {{ projectName(approval.projectId) }} · {{ gateAction(approval.action) }} ·
                <span class="mono">{{ shortSha(approval.sha) }}</span> · {{ formatTime(approval.createdAt) }}
              </span>
              <span
                v-if="approval.state === 'pending'"
                class="meta"
                :class="expiresSoon(approval) ? 'soon' : 'muted'"
              >
                expires in {{ formatCountdown(approval.expiresAt) }}
              </span>
            </RouterLink>
          </li>
        </ul>
      </div>
      <div class="pane">
        <ApprovalDetail v-if="store.selected" :approval-id="store.selected.id" />
        <p v-else-if="store.loaded" class="xp-type-title empty">{{ empty }}</p>
      </div>
    </div>
  </section>
</template>

<style scoped>
.filters button.selected {
  background: var(--xp-color-surface-selected);
  border-color: var(--xp-color-border-strong);
}

.inbox {
  display: grid;
  grid-template-columns: minmax(0, 340px) minmax(0, 1fr);
  gap: var(--xp-space-16);
}

.list h2 {
  margin: 0 0 var(--xp-space-8);
}

.list ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

.row {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-2);
  margin-bottom: var(--xp-space-4);
  padding: var(--xp-space-8) var(--xp-space-10);
  color: var(--xp-color-text-primary);
  text-decoration: none;
  border: var(--xp-border-width-hairline) solid transparent;
  border-radius: var(--xp-radius-md);
}

.row:hover {
  background: var(--xp-color-surface-hover);
}

.row.selected {
  background: var(--xp-color-surface-selected);
  border-color: var(--xp-color-border-strong);
}

.row-title {
  display: flex;
  align-items: center;
  gap: var(--xp-space-8);
  min-width: 0;
  overflow-wrap: anywhere;
}

.meta {
  font: var(--xp-type-caption);
  overflow-wrap: anywhere;
}

.soon {
  color: var(--xp-color-status-caution-on-container);
}

.empty {
  margin-top: var(--xp-space-24);
  text-align: center;
  color: var(--xp-color-text-secondary);
}

@media (max-width: 760px) {
  .inbox {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
