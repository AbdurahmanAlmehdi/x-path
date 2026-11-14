<script setup lang="ts">
import { onMounted } from 'vue'

import { useFollowing } from '@/ui/following'

import { useProjectsStore } from '../stores/projects'

const projects = useProjectsStore()

onMounted(() => projects.load())
useFollowing(projects.follow)

function appCount(count: number): string {
  return count === 1 ? '1 app' : `${count} apps`
}
</script>

<template>
  <section>
    <header class="page-header">
      <h1 class="xp-type-headline">Projects</h1>
    </header>
    <p v-if="projects.error" class="alert" role="alert">{{ projects.error }}</p>
    <p v-if="!projects.loaded" class="muted">Loading…</p>
    <div v-else-if="projects.projects.length === 0 && !projects.error" class="panel">
      <h2 class="xp-type-title">No projects yet</h2>
      <p class="muted">
        Add the repository of a Flutter app from the Mac app or with
        <code>xp projects add &lt;folder or repository&gt;</code>.
      </p>
    </div>
    <ul v-else class="projects">
      <li v-for="project in projects.projects" :key="project.id">
        <RouterLink :to="{ name: 'project', params: { id: project.id } }" class="project">
          <span class="xp-type-title">{{ project.fullName }}</span>
          <span class="muted">
            {{ project.host }} · {{ project.defaultBaseBranch }} ·
            {{ appCount(project.profile.apps.length) }}
          </span>
        </RouterLink>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.projects {
  list-style: none;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: var(--xp-space-12);
  margin: 0;
  padding: 0;
}

.project {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
  padding: var(--xp-space-12) var(--xp-space-16);
  color: var(--xp-color-text-primary);
  text-decoration: none;
  background: var(--xp-color-surface-base);
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
  border-radius: var(--xp-radius-lg);
  overflow-wrap: anywhere;
}

.project:hover {
  background: var(--xp-color-surface-hover);
}
</style>
