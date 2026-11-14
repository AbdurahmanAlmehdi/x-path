<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

import { useApprovalStore } from '../stores/approval'
import { deciderOf } from '../labels'
import ApprovalFacts from './ApprovalFacts.vue'
import ApprovalHeading from './ApprovalHeading.vue'

const props = defineProps<{
  /** Whether the review opens at the denial. */
  deny?: boolean
}>()

const store = useApprovalStore()
const denying = ref(props.deny ?? false)
const reason = ref('')
const dialog = ref<HTMLElement | null>(null)

onMounted(() => dialog.value?.focus())

/** It ended elsewhere first: decided on another device, or expired. */
const settled = computed(() => store.approval !== null && !store.pending)

const settledMessage = computed(() => {
  const approval = store.approval
  if (!approval) return ''
  if (approval.state === 'expired') {
    return 'This approval expired: it counts as denied. Dispatch again to ask anew.'
  }
  return `Already ${approval.state} by ${deciderOf(approval)}. The first decision counts; nothing to do here.`
})

async function decide(decision: 'approve' | 'deny') {
  if (await store.decide(decision, reason.value)) store.close()
}

/** Return never approves, not even on a focused button; ⌘↩ or Ctrl+↩ does. */
function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    store.close()
    return
  }
  if (event.key !== 'Enter') return
  event.preventDefault()
  if ((event.metaKey || event.ctrlKey) && !denying.value) void decide('approve')
}
</script>

<template>
  <div class="scrim" @click.self="store.close()">
    <div
      ref="dialog"
      class="dialog"
      role="dialog"
      aria-modal="true"
      aria-label="Review the approval"
      tabindex="-1"
      @keydown="onKeydown"
    >
      <div class="body">
        <template v-if="store.approval">
          <ApprovalHeading :approval="store.approval" />
          <p v-if="settled" class="notice" role="status" data-testid="already-decided">{{ settledMessage }}</p>
          <ApprovalFacts
            :approval="store.approval"
            :job="store.job"
            :release="store.release"
            :consequence="!settled"
          />
          <label v-if="denying && !settled" class="reason">
            <span class="xp-type-label muted">Reason (optional)</span>
            <input v-model="reason" type="text" placeholder="Why, for the record" />
          </label>
          <p v-if="store.decisionError && !settled" class="alert" role="alert">{{ store.decisionError }}</p>
        </template>
        <p v-else-if="store.error" class="alert" role="alert">{{ store.error }}</p>
        <p v-else-if="store.missing" class="notice">This approval cannot be read on this engine.</p>
        <p v-else class="muted">Loading…</p>
      </div>
      <footer class="footer">
        <span class="muted hint">{{ !settled && !denying && store.approval ? 'Return never approves. ⌘↩ or Ctrl+↩ approves.' : '' }}</span>
        <template v-if="settled || !store.approval">
          <button type="button" @click="store.close()">Close</button>
        </template>
        <template v-else-if="denying">
          <button type="button" @click="denying = false">Back</button>
          <button type="button" class="danger" :disabled="!store.canDeny" @click="decide('deny')">
            {{ store.deciding === 'deny' ? 'Denying…' : 'Deny' }}
          </button>
        </template>
        <template v-else>
          <button type="button" @click="store.close()">Cancel</button>
          <button type="button" :disabled="!store.canDeny" @click="denying = true">Deny…</button>
          <button
            type="button"
            class="primary"
            :disabled="!store.canApprove"
            :title="store.armed ? undefined : 'Approve arms in a moment'"
            @click="decide('approve')"
          >
            {{ store.deciding === 'approve' ? 'Approving…' : 'Approve' }}
          </button>
        </template>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.scrim {
  position: fixed;
  inset: 0;
  z-index: 10;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--xp-space-32) var(--xp-space-16) var(--xp-space-16);
  overflow-y: auto;
  background: var(--xp-color-scrim-default);
}

.dialog {
  width: min(600px, 100%);
  background: var(--xp-color-surface-overlay);
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-strong);
  border-radius: var(--xp-radius-lg);
  box-shadow: var(--xp-elevation-3);
}

.dialog:focus {
  outline: none;
}

.body {
  padding: var(--xp-space-16) var(--xp-space-20);
}

.reason {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
  margin-top: var(--xp-space-12);
}

.footer {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-8);
  padding: var(--xp-space-12) var(--xp-space-20);
  border-top: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
}

.hint {
  flex: 1;
  min-width: 0;
}
</style>
