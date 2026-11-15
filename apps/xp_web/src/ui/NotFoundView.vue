<script setup lang="ts">
import { useRoute } from 'vue-router'

const route = useRoute()
</script>

<template>
  <section>
    <h1 class="xp-type-headline">Nothing here yet</h1>
    <p class="xp-type-body">
      The dashboard has no page at <code>{{ route.path }}</code>.
      <RouterLink to="/">Go home</RouterLink>
    </p>
  </section>
</template>
