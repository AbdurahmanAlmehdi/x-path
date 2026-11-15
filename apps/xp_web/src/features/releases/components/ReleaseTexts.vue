<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import type { Release } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'

import { useReleasesStore } from '../stores/releases'

const props = defineProps<{ release: Release }>()

const session = useSessionStore()
const board = useReleasesStore()

const whatsNew = ref(props.release.whatsNew ?? '')
const whatToTest = ref(props.release.whatToTest ?? '')

function edited(release: Release): boolean {
  return (
    whatsNew.value.trim() !== (release.whatsNew ?? '') ||
    whatToTest.value.trim() !== (release.whatToTest ?? '')
  )
}

// Another release, or texts saved elsewhere: show what the engine keeps,
// unless the person is typing.
watch(
  () => props.release,
  (release, before) => {
    if (release.id !== before.id || !edited(before)) {
      whatsNew.value = release.whatsNew ?? ''
      whatToTest.value = release.whatToTest ?? ''
    }
  },
)

const editable = computed(() => session.can('release') && props.release.state !== 'abandoned')

function save() {
  void board.saveTexts({ whatsNew: whatsNew.value, whatToTest: whatToTest.value })
}
</script>

<template>
  <section class="panel texts">
    <h2 class="xp-type-label muted">Store texts</h2>
    <label>
      <span class="xp-type-label">What's new</span>
      <textarea v-model="whatsNew" rows="4" :disabled="!editable" />
    </label>
    <label>
      <span class="xp-type-label">What to test</span>
      <textarea v-model="whatToTest" rows="4" :disabled="!editable" />
    </label>
    <p class="muted caption">
      Uploads send them when they run: What's new to Google Play, What to test to Firebase testers. Notes a
      workflow gives win.
    </p>
    <button
      v-if="editable"
      type="button"
      :disabled="board.command !== null || !edited(release)"
      @click="save"
    >
      {{ board.command === 'savingTexts' ? 'Saving…' : 'Save texts' }}
    </button>
  </section>
</template>

<style scoped>
.texts label {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
  margin-bottom: var(--xp-space-8);
}

.texts textarea {
  width: 100%;
  resize: vertical;
  font: var(--xp-type-body);
}

.caption {
  font: var(--xp-type-caption);
}
</style>
