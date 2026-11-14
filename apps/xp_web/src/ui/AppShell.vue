<script setup lang="ts">
import { useRouter } from 'vue-router'

import { navigation } from '@/app/navigation'
import { usePendingApprovalsStore } from '@/features/approvals/stores/pending'
import { useSessionStore } from '@/features/session/stores/session'

import { useFollowing } from './following'

const session = useSessionStore()
const pending = usePendingApprovalsStore()
const router = useRouter()

useFollowing(pending.follow)

async function signOut() {
  await session.signOut()
  await router.replace({ name: 'sign-in' })
}
</script>

<template>
  <div class="shell">
    <header class="toolbar">
      <RouterLink to="/" class="brand xp-type-title">XPath</RouterLink>
      <div class="who">
        <span class="xp-type-body-strong" data-testid="person-name">{{ session.person?.name }}</span>
        <span class="xp-type-label role">{{ session.person?.role }}</span>
        <button type="button" @click="signOut">Sign out</button>
      </div>
    </header>
    <nav class="sidebar" aria-label="Main">
      <section v-for="section in navigation" :key="section.label">
        <h2 class="xp-type-label">{{ section.label }}</h2>
        <ul>
          <li v-for="item in section.items" :key="item.to">
            <RouterLink :to="item.to" class="xp-type-body">
              {{ item.label }}
              <span
                v-if="item.needsYou && pending.count > 0"
                class="needs-you xp-type-label"
                data-testid="needs-you"
                :aria-label="`${pending.count} waiting`"
              >{{ pending.count }}</span>
            </RouterLink>
          </li>
        </ul>
      </section>
    </nav>
    <main class="content">
      <RouterView />
    </main>
  </div>
</template>

<style scoped>
.shell {
  min-height: 100vh;
  display: grid;
  grid-template-columns: var(--xp-size-sidebar-width) minmax(0, 1fr);
  grid-template-rows: var(--xp-size-toolbar-height) 1fr;
  grid-template-areas:
    'toolbar toolbar'
    'sidebar content';
}

.toolbar {
  grid-area: toolbar;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--xp-space-12);
  padding: 0 var(--xp-space-16);
  background: var(--xp-color-surface-base);
  border-bottom: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
}

.brand {
  color: var(--xp-color-text-primary);
  text-decoration: none;
}

.who {
  display: flex;
  align-items: center;
  gap: var(--xp-space-8);
  min-width: 0;
}

.role {
  color: var(--xp-color-text-tertiary);
}

.sidebar {
  grid-area: sidebar;
  padding: var(--xp-space-12) var(--xp-space-8);
  background: var(--xp-color-surface-sidebar);
  border-right: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
}

.sidebar h2 {
  margin: var(--xp-space-12) var(--xp-space-8) var(--xp-space-4);
  color: var(--xp-color-text-tertiary);
}

.sidebar ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

.sidebar a {
  display: flex;
  align-items: center;
  gap: var(--xp-space-8);
  height: var(--xp-size-row-sidebar);
  padding: 0 var(--xp-space-8);
  border-radius: var(--xp-radius-md);
  color: var(--xp-color-text-primary);
  text-decoration: none;
}

.needs-you {
  margin-left: auto;
  min-width: 20px;
  padding: 0 var(--xp-space-6);
  text-align: center;
  border-radius: var(--xp-radius-sm);
  color: var(--xp-color-status-attention-on-container);
  background: var(--xp-color-status-attention-container);
}

.sidebar a:hover {
  background: var(--xp-color-surface-hover);
}

.sidebar a.router-link-active {
  background: var(--xp-color-surface-selected);
  box-shadow: var(--xp-elevation-1);
}

.content {
  grid-area: content;
  min-width: 0;
  padding: var(--xp-space-24);
  background: var(--xp-color-surface-window);
}

@media (max-width: 760px) {
  .shell {
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: var(--xp-size-toolbar-height) auto 1fr;
    grid-template-areas:
      'toolbar'
      'sidebar'
      'content';
  }

  .sidebar {
    display: flex;
    gap: var(--xp-space-16);
    overflow-x: auto;
    border-right: 0;
    border-bottom: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
  }

  .sidebar ul {
    display: flex;
  }

  .content {
    padding: var(--xp-space-16);
  }
}
</style>
