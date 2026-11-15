<script setup lang="ts">
import { ref, watch } from 'vue'

import { useSessionStore } from '@/features/session/stores/session'
import { useFollowing } from '@/ui/following'

import { useApprovalStore } from '../stores/approval'
import ApprovalFacts from './ApprovalFacts.vue'
import ApprovalHeading from './ApprovalHeading.vue'
import ApprovalReview from './ApprovalReview.vue'

const props = defineProps<{ approvalId: string }>()

const session = useSessionStore()
const store = useApprovalStore()
/** Whether the review opens at the denial. */
const denyFirst = ref(false)

watch(
  () => props.approvalId,
  (id) => void store.open(id),
  { immediate: true },
)
useFollowing(store.follow)

function review(deny: boolean) {
  denyFirst.value = deny
  store.review()
}
</script>

<template>
  <div class="detail" data-testid="approval-detail">
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="store.missing" class="notice">This approval cannot be read on this engine.</p>
    <template v-if="store.approval && store.approval.id === approvalId">
      <ApprovalHeading :approval="store.approval" />
      <ApprovalFacts
        :approval="store.approval"
        :job="store.job"
        :release="store.release"
        :consequence="store.pending"
      />
      <template v-if="store.pending">
        <div v-if="session.can('decide_approval')" class="actions">
          <button type="button" @click="review(true)">Deny…</button>
          <button type="button" class="primary" @click="review(false)">Approve…</button>
        </div>
        <p v-else class="muted" data-testid="cannot-decide">
          A releaser or an admin decides this approval; your role cannot.
        </p>
      </template>
    </template>
    <ApprovalReview v-if="store.reviewing" :deny="denyFirst" />
  </div>
</template>
