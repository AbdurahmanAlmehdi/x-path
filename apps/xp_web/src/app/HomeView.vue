<script setup lang="ts">
import { useSessionStore } from '@/features/session/stores/session'

const session = useSessionStore()
</script>

<template>
  <section>
    <h1 class="xp-type-headline">Welcome, {{ session.person?.name }}</h1>
    <p class="xp-type-body">
      You are signed in as <strong>{{ session.person?.role }}</strong>. Pick a section on the left.
    </p>
  </section>
</template>
