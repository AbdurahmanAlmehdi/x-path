<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { useProjectsStore } from '@/features/projects/stores/projects'
import { useSessionStore } from '@/features/session/stores/session'
import Badge from '@/ui/Badge.vue'
import CopyButton from '@/ui/CopyButton.vue'
import { useFollowing } from '@/ui/following'
import { formatTime, shortSha, versionLabel } from '@/ui/format'

import ReleaseTexts from '../components/ReleaseTexts.vue'
import StoreLane from '../components/StoreLane.vue'
import {
  mergeCaption,
  minVersionText,
  releaseHero,
  releasePatches,
  releaseStatus,
  releaseStores,
  releaseTimeline,
  variableList,
} from '../labels'
import { useReleasesStore } from '../stores/releases'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const board = useReleasesStore()
const projects = useProjectsStore()

const projectId = computed(() => String(route.params.id))
const releaseId = computed(() => (route.params.releaseId ? String(route.params.releaseId) : null))

watch(projectId, (id) => void board.open(id, releaseId.value), { immediate: true })
watch(releaseId, (id) => board.select(id))
void projects.load()
useFollowing(board.follow, projects.follow)

const project = computed(() => projects.projects.find((each) => each.id === projectId.value))
const gone = computed(() => projects.loaded && !projects.error && !project.value)
const name = computed(() => project.value?.fullName.split('/').at(-1) ?? projectId.value)
const release = computed(() => board.release)
const base = computed(() => release.value?.baseBranch ?? 'the base branch')
/** The run of the newest build of the release shown. */
const buildRun = computed(() => release.value?.builds.at(-1)?.runId)

const title = computed(() =>
  release.value ? `Release ${versionLabel(release.value.version, release.value.build)}` : 'Releases',
)
const subtitle = computed(() =>
  release.value
    ? [name.value, release.value.flavor, release.value.tag].filter(Boolean).join(' · ')
    : name.value,
)

const caption = computed(() =>
  release.value
    ? mergeCaption(release.value, board.approvals, (store) => board.readsStore(release.value!, store))
    : '',
)
const timeline = computed(() =>
  release.value ? releaseTimeline(release.value, board.approvals, board.history) : [],
)
const patches = computed(() => releasePatches(board.history))

async function merge() {
  const run = await board.merge()
  if (run) await router.push({ name: 'run', params: { id: run.id } })
}
</script>

<template>
  <section>
    <p v-if="gone" class="notice">This project is no longer on the engine.</p>
    <template v-else>
      <header class="page-header">
        <div>
          <h1 class="xp-type-headline">{{ title }}</h1>
          <p class="muted">
            <RouterLink :to="{ name: 'project', params: { id: projectId } }">{{ subtitle }}</RouterLink>
          </p>
        </div>
        <div class="actions">
          <button
            v-if="release && session.can('develop')"
            type="button"
            title="Ask the stores now instead of waiting up to ten minutes"
            :disabled="board.command !== null"
            @click="board.refresh()"
          >
            {{ board.command === 'refreshing' ? 'Refreshing…' : 'Refresh' }}
          </button>
          <RouterLink v-if="buildRun" :to="{ name: 'run', params: { id: buildRun } }" class="button">
            Open run
          </RouterLink>
        </div>
      </header>

      <p v-if="release && release.state === 'live'" class="notice reminder">
        <strong>Reminder</strong>
        If this release is a forced update, raise
        {{ variableList(release.stores.map((status) => status.store)) }} to {{ release.version }}: every
        store has it live.
      </p>
      <p v-if="board.commandError" class="alert" role="alert">{{ board.commandError }}</p>
      <p v-if="board.notice" class="notice" role="status">{{ board.notice }}</p>
      <p v-if="board.error" class="alert" role="alert">{{ board.error }}</p>

      <div class="board" :class="{ picking: board.releases.length > 1 }">
        <nav v-if="board.releases.length > 1" class="picker" aria-label="Releases">
          <RouterLink
            v-for="each in board.releases"
            :key="each.id"
            :to="{ name: 'releases', params: { id: projectId, releaseId: each.id } }"
            class="pick"
            :class="{ selected: each.id === release?.id }"
          >
            <span class="xp-type-body-strong mono">{{ versionLabel(each.version, each.build) }}</span>
            <span class="muted">{{ each.flavor }} · {{ releaseStatus(each.state).label }}</span>
          </RouterLink>
        </nav>

        <div v-if="release" class="shown">
          <section class="hero">
            <div>
              <p class="hero-state">
                <Badge :status="releaseStatus(release.state)" />
                <span class="xp-type-title" data-testid="release-hero">{{ releaseHero(release) }}</span>
              </p>
              <p class="muted meta">
                {{ release.flavor }}
                <template v-if="release.headSha"> · <span class="mono">{{ shortSha(release.headSha) }}</span></template>
                <template v-if="release.tag"> · <span class="mono">{{ release.tag }}</span></template>
                <template v-if="release.branch">
                  · <span class="mono">{{ release.branch }}</span> → {{ base }}
                </template>
              </p>
            </div>
            <div class="merge">
              <button
                v-if="release.state !== 'merged' && session.can('develop')"
                type="button"
                class="primary"
                :disabled="!release.mergeEnabled || board.command !== null"
                @click="merge"
              >
                Merge into {{ base }}
              </button>
              <p class="muted" data-testid="merge-caption">{{ caption }}</p>
            </div>
          </section>

          <h2 class="xp-type-label muted">Store lanes</h2>
          <div class="lanes">
            <StoreLane v-for="store in releaseStores" :key="store" :release="release" :store="store" />
          </div>

          <div class="columns">
            <section class="panel">
              <h2 class="xp-type-label muted">Timeline <span class="newest">newest first</span></h2>
              <ol class="timeline">
                <li v-for="(entry, index) in timeline" :key="index">
                  <Badge :status="entry.status" />
                  <span class="entry">
                    <span>{{ entry.title }}</span>
                    <span v-if="entry.detail" class="muted detail">{{ entry.detail }}</span>
                  </span>
                  <span class="mono muted when">{{ formatTime(entry.at) }}</span>
                </li>
              </ol>
            </section>

            <div>
              <section class="panel notes">
                <h2 class="xp-type-label muted">
                  Release notes
                  <span v-if="board.notes" class="newest">
                    {{ board.notes.from ? `since ${board.notes.from} · ` : ''
                    }}{{ board.notes.commits === 1 ? '1 commit' : `${board.notes.commits} commits` }}
                  </span>
                </h2>
                <p v-if="!release.headSha" class="muted">The notes are ready once the release is tagged.</p>
                <p v-else-if="board.notesError" class="notice">{{ board.notesError }}</p>
                <p v-else-if="!board.notes" class="muted">Loading…</p>
                <template v-else>
                  <p v-if="board.notes.groups.length === 0" class="muted">Nothing changed since the release before.</p>
                  <div v-for="group in board.notes.groups" :key="group.type" class="group">
                    <h3 class="xp-type-body-strong">{{ group.title }}</h3>
                    <ul>
                      <li v-for="item in group.items" :key="item.sha">
                        {{ [item.scope, item.description].filter(Boolean).join(': ') }}
                      </li>
                    </ul>
                  </div>
                  <div class="actions">
                    <CopyButton label="Copy for Slack" :text="board.notes.slack" />
                    <CopyButton label="Copy for WhatsApp" :text="board.notes.whatsapp" />
                  </div>
                </template>
              </section>
              <ReleaseTexts :release="release" />
            </div>

            <div>
              <section class="panel">
                <h2 class="xp-type-label muted">Forced update</h2>
                <p>{{ minVersionText(release) }}</p>
              </section>

              <section class="panel" data-testid="release-pr">
                <h2 class="xp-type-label muted">
                  Release PR <span v-if="release.prNumber" class="newest mono">#{{ release.prNumber }}</span>
                </h2>
                <p v-if="release.prNumber === undefined" class="muted">
                  No pull request yet: the release opens one once it is tagged.
                </p>
                <template v-else>
                  <p class="mono">
                    <template v-if="release.branch">{{ release.branch }} → </template>{{ base }}
                  </p>
                  <p class="muted">
                    {{
                      release.state === 'merged'
                        ? `Merged with a merge commit · ${shortSha(release.mergeCommit ?? '')}`
                        : release.tag
                          ? `Merging adds no tag: ${release.tag} was tagged when the build was recorded.`
                          : 'The release is tagged when its build is recorded.'
                    }}
                  </p>
                  <div class="actions">
                    <CopyButton v-if="release.prUrl" label="Copy link" :text="release.prUrl" />
                    <RouterLink
                      v-if="release.mergeRunId"
                      :to="{ name: 'run', params: { id: release.mergeRunId } }"
                    >
                      Open merge run
                    </RouterLink>
                  </div>
                </template>
              </section>

              <section v-if="patches.length > 0" class="panel" data-testid="patches">
                <h2 class="xp-type-label muted">Shorebird patches</h2>
                <ul class="patches">
                  <li v-for="patch in patches" :key="patch.number">
                    <span>
                      Patch {{ patch.number }} ·
                      {{
                        patch.state === 'promoted'
                          ? 'On stable'
                          : patch.state === 'rolledBack'
                            ? 'Rolled back'
                            : 'Published'
                      }}
                    </span>
                    <span v-if="session.can('develop')" class="actions">
                      <button
                        v-if="patch.state !== 'promoted'"
                        type="button"
                        :disabled="board.command !== null"
                        @click="board.movePatch(patch.number, 'promote')"
                      >
                        Promote
                      </button>
                      <button
                        v-if="patch.state !== 'rolledBack'"
                        type="button"
                        :disabled="board.command !== null"
                        @click="board.movePatch(patch.number, 'rollback')"
                      >
                        Roll back
                      </button>
                    </span>
                  </li>
                </ul>
                <p class="muted">Each change waits for your approval.</p>
              </section>
            </div>
          </div>
        </div>
        <p v-else-if="!board.loaded" class="muted">Loading…</p>
        <div v-else-if="!board.error" class="empty">
          <p class="xp-type-title">No release yet</p>
          <p v-if="project && project.host !== 'github.com'" class="muted">
            Production releases push and open a pull request on GitHub, so they do not run for a project on
            {{ project.host }}. Dev builds and tests do.
          </p>
          <template v-else>
            <p class="muted">A production release dispatched from the project shows up here.</p>
            <RouterLink
              v-if="session.can('develop')"
              :to="{ name: 'dispatch', params: { id: projectId }, query: { workflow: 'prod-release' } }"
              class="button primary"
            >
              Dispatch Prod release…
            </RouterLink>
          </template>
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
.reminder strong {
  margin-right: var(--xp-space-8);
}

.board {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: var(--xp-space-16);
}

.board.picking {
  grid-template-columns: minmax(0, 220px) minmax(0, 1fr);
}

.picker {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
}

.pick {
  display: flex;
  flex-direction: column;
  padding: var(--xp-space-6) var(--xp-space-8);
  color: var(--xp-color-text-primary);
  text-decoration: none;
  border-radius: var(--xp-radius-md);
}

.pick:hover {
  background: var(--xp-color-surface-hover);
}

.pick.selected {
  background: var(--xp-color-surface-selected);
}

.hero {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: var(--xp-space-16);
  margin-bottom: var(--xp-space-16);
}

.hero-state {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-8);
}

.meta {
  overflow-wrap: anywhere;
}

.merge {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  max-width: 360px;
  text-align: right;
}

.merge p {
  margin-top: var(--xp-space-4);
}

.lanes {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--xp-space-16);
}

.columns {
  display: grid;
  grid-template-columns: 5fr 4fr 4fr;
  gap: var(--xp-space-16);
}

.columns > * {
  min-width: 0;
}

.newest {
  float: right;
  text-transform: none;
}

.timeline,
.patches,
.group ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

.timeline li {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: var(--xp-space-8);
  align-items: start;
  margin-bottom: var(--xp-space-8);
}

.entry {
  display: flex;
  flex-direction: column;
  overflow-wrap: anywhere;
}

.detail,
.when {
  font: var(--xp-type-caption);
}

.group h3 {
  margin: var(--xp-space-8) 0 var(--xp-space-2);
}

.group li::before {
  content: '•  ';
}

.patches li {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--xp-space-8);
  margin-bottom: var(--xp-space-8);
}

.empty {
  margin-top: var(--xp-space-40);
  text-align: center;
}

@media (max-width: 1100px) {
  .columns {
    grid-template-columns: minmax(0, 1fr);
  }
}

@media (max-width: 760px) {
  .board.picking,
  .lanes {
    grid-template-columns: minmax(0, 1fr);
  }

  .merge {
    align-items: flex-start;
    text-align: left;
  }
}
</style>
