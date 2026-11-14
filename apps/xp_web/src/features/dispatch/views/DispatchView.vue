<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import type { VersionBump, WorkflowInput } from '@/api/client'
import { useProjectStore } from '@/features/projects/stores/project'
import { useSessionStore } from '@/features/session/stores/session'
import { pubspecLabel } from '@/ui/format'

import { releaseValue, useDispatchStore } from '../stores/dispatch'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const projectStore = useProjectStore()
const form = useDispatchStore()

const bumps: Array<{ value: VersionBump; label: string }> = [
  { value: 'keep', label: 'Keep' },
  { value: 'patch', label: 'Patch' },
  { value: 'minor', label: 'Minor' },
  { value: 'major', label: 'Major' },
]

watch(
  () => String(route.params.id),
  async (id) => {
    if (!session.can('develop')) return
    await projectStore.open(id)
    const workflow = route.query.workflow
    if (projectStore.project) {
      await form.start(projectStore.project, typeof workflow === 'string' ? workflow : undefined)
    }
  },
  { immediate: true },
)

const flavorNames = computed(() =>
  (form.chosenApp?.flavors ?? []).filter((flavor) => !flavor.implicit).map((flavor) => flavor.name),
)
const platformNames = computed(() => {
  const app = form.chosenApp
  return [
    ...(app?.hasAndroid ? [{ value: 'android', label: 'Android' }] : []),
    ...(app?.hasIos ? [{ value: 'ios', label: 'iOS' }] : []),
  ]
})

const buttonLabel = computed(() => {
  if (form.preview === null && form.refNotice !== null) return 'Dispatch'
  return form.jobCount === 1 ? 'Dispatch 1 job' : `Dispatch ${form.jobCount} jobs`
})

const stageCount = computed(() => form.preview?.stages.length ?? 0)

function inputValue(input: WorkflowInput): unknown {
  return form.inputs[input.name] ?? input.default
}

/** The text a JSON input shows: what was typed, else the value as JSON. */
function jsonText(input: WorkflowInput): string {
  const value = inputValue(input)
  if (value === undefined) return ''
  return typeof value === 'string' ? value : JSON.stringify(value)
}

function setJson(input: WorkflowInput, text: string) {
  if (text.trim() === '') {
    form.setInput(input.name, undefined, { typed: true })
    return
  }
  try {
    form.setInput(input.name, JSON.parse(text), { typed: true })
  } catch {
    form.setInput(input.name, text, { valid: false, typed: true })
  }
}

function where(job: { local: boolean; runner?: string; waitReason?: string; narrowing?: string[] }): string {
  const place = job.local ? 'the engine' : (job.runner ?? 'a runner')
  const parts = [`on ${place}`]
  if (job.narrowing?.length) parts.push(`needs a Mac for iOS: ${job.narrowing.join(', ')}`)
  if (job.waitReason) parts.push(`waits: ${job.waitReason}`)
  return parts.join(' · ')
}

function valueOf(event: Event): string {
  return (event.target as HTMLInputElement).value
}

async function dispatch() {
  const run = await form.submit()
  if (run) await router.push({ name: 'run', params: { id: run.id } })
}
</script>

<template>
  <section class="dispatch">
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Dispatch</h1>
        <p v-if="projectStore.project" class="muted">{{ projectStore.project.fullName }}</p>
      </div>
    </header>

    <p v-if="!session.can('develop')" class="notice">
      Your role cannot dispatch. An admin can make you a developer.
    </p>
    <template v-else>
      <p v-if="projectStore.missing" class="notice">This project is no longer on the engine.</p>
      <p v-if="projectStore.error" class="alert" role="alert">{{ projectStore.error }}</p>
      <p v-if="form.loading" class="muted">Loading…</p>
      <p v-else-if="form.workflows.length === 0 && !form.error" class="notice">The project has no workflow.</p>
      <div v-else class="panel form">
        <label class="field">
          <span class="xp-type-label">Workflow</span>
          <select :value="form.workflow?.id" @change="form.choose(valueOf($event))">
            <option v-for="each in form.workflows" :key="each.id" :value="each.id">
              {{ each.title ?? each.name }}{{ each.builtin ? ' (built-in)' : '' }}
            </option>
          </select>
        </label>

        <label v-if="(projectStore.project?.profile.apps.length ?? 0) > 1" class="field">
          <span class="xp-type-label">App</span>
          <select :value="form.app" @change="form.chooseApp(valueOf($event))">
            <option v-for="app in projectStore.project?.profile.apps" :key="app.path" :value="app.path">
              {{ app.name }} ({{ app.path }})
            </option>
          </select>
        </label>

        <fieldset v-if="flavorNames.length > 0" class="field">
          <legend class="xp-type-label">Flavors</legend>
          <label v-for="flavor in flavorNames" :key="flavor" class="choice">
            <input type="checkbox" :checked="form.chosenFlavors.includes(flavor)" @change="form.toggleFlavor(flavor)" />
            {{ flavor }}
          </label>
        </fieldset>

        <fieldset v-if="platformNames.length > 0" class="field">
          <legend class="xp-type-label">Platforms</legend>
          <label v-for="platform in platformNames" :key="platform.value" class="choice">
            <input
              type="checkbox"
              :checked="form.chosenPlatforms.includes(platform.value)"
              @change="form.togglePlatform(platform.value)"
            />
            {{ platform.label }}
          </label>
        </fieldset>

        <label class="field">
          <span class="xp-type-label">Ref</span>
          <input :value="form.gitRef" spellcheck="false" placeholder="branch, tag or commit" @input="form.setRef(valueOf($event))" />
        </label>

        <fieldset v-if="form.bumps" class="field">
          <legend class="xp-type-label">Version</legend>
          <div class="bumps">
            <label v-for="bump in bumps" :key="bump.value" class="choice">
              <input
                type="radio"
                name="bump"
                :value="bump.value"
                :checked="form.bump === bump.value"
                :disabled="form.version.trim() !== ''"
                @change="form.setBump(bump.value)"
              />
              {{ bump.label }}
            </label>
            <input
              :value="form.version"
              class="version"
              placeholder="or x.y.z"
              aria-label="Version to release"
              spellcheck="false"
              @input="form.setVersion(valueOf($event))"
            />
          </div>
          <p v-if="form.preview?.currentVersion" class="xp-type-caption muted">
            <template v-if="form.preview.version">{{ form.preview.version }} · </template>from
            {{ pubspecLabel(form.preview.currentVersion) }} in the pubspec of the commit
          </p>
        </fieldset>

        <fieldset v-if="(form.workflow?.inputs?.length ?? 0) > 0" class="field">
          <legend class="xp-type-label">Inputs</legend>
          <p v-if="form.noReleases" class="notice">
            No releases yet: this workflow needs a release that reached a store.
          </p>
          <div v-for="input in form.workflow?.inputs" :key="input.name" class="input">
            <label :for="`input-${input.name}`" class="mono">{{ input.name }}{{ input.required ? ' *' : '' }}</label>
            <select
              v-if="input.type === 'boolean'"
              :id="`input-${input.name}`"
              :value="String(inputValue(input) ?? false)"
              @change="form.setInput(input.name, valueOf($event) === 'true')"
            >
              <option value="true">Yes</option>
              <option value="false">No</option>
            </select>
            <select
              v-else-if="input.type === 'choice'"
              :id="`input-${input.name}`"
              :value="inputValue(input) ?? input.options?.[0]"
              @change="form.setInput(input.name, valueOf($event))"
            >
              <option v-for="option in input.options" :key="option" :value="option">{{ option }}</option>
            </select>
            <select
              v-else-if="input.type === 'release'"
              :id="`input-${input.name}`"
              :value="inputValue(input)"
              @change="form.setInput(input.name, valueOf($event))"
            >
              <option v-for="release in form.releases ?? []" :key="release.id" :value="releaseValue(release)">
                {{ releaseValue(release) }} · {{ release.flavor }}
              </option>
            </select>
            <textarea
              v-else-if="input.type === 'json'"
              :id="`input-${input.name}`"
              :value="jsonText(input)"
              rows="2"
              spellcheck="false"
              :aria-invalid="form.invalidInputs.includes(input.name)"
              @input="setJson(input, valueOf($event))"
            ></textarea>
            <input
              v-else
              :id="`input-${input.name}`"
              :value="inputValue(input) ?? ''"
              spellcheck="false"
              @input="form.setInput(input.name, valueOf($event), { typed: true })"
            />
            <p v-if="form.invalidInputs.includes(input.name)" class="invalid xp-type-caption">Not valid JSON.</p>
            <p v-else-if="input.description" class="xp-type-caption muted">{{ input.description }}</p>
          </div>
        </fieldset>

        <section class="preview" aria-live="polite">
          <p v-if="form.error" class="alert" role="alert">{{ form.error }}</p>
          <p v-if="form.refNotice" class="notice">{{ form.refNotice }}</p>
          <p v-if="form.previewing" class="muted">Planning…</p>
          <template v-else-if="form.preview">
            <p v-if="form.jobCount === 0" class="notice">Nothing would run for these flavors and platforms.</p>
            <template v-else>
              <h2 class="xp-type-title" data-testid="will-run">
                Will run · {{ form.jobCount === 1 ? '1 job' : `${form.jobCount} jobs` }} in
                {{ stageCount === 1 ? '1 stage' : `${stageCount} stages` }}
              </h2>
              <p v-if="form.gates.length > 0" class="attention">
                Waits for approval: {{ form.gates.map(form.gateLabel).join(', ') }}
              </p>
            </template>
            <div v-for="stage in form.preview.stages" :key="stage.name" class="stage">
              <h3 class="xp-type-label muted">{{ stage.name }}</h3>
              <ul>
                <li v-for="job in stage.jobs" :key="job.name">
                  <span class="xp-type-body-strong">{{ job.name }}</span> <span class="muted">{{ where(job) }}</span>
                </li>
              </ul>
            </div>
            <ul v-if="form.preview.skipped.length > 0" class="skipped">
              <li v-for="job in form.preview.skipped" :key="`${job.stage}-${job.name}`" :class="{ blocks: job.blocks }">
                {{ job.name }}: {{ job.blocks ? 'cannot run' : 'skipped' }}, {{ job.reason }}
              </li>
            </ul>
          </template>
        </section>

        <div class="buttons">
          <RouterLink
            v-if="projectStore.project"
            :to="{ name: 'project', params: { id: projectStore.project.id } }"
            class="button"
          >
            Cancel
          </RouterLink>
          <button
            type="button"
            class="primary"
            :disabled="!form.canDispatch"
            data-testid="dispatch"
            @click="dispatch"
          >
            {{ form.submitting ? 'Dispatching…' : buttonLabel }}
          </button>
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
.dispatch {
  max-width: 720px;
}

.form {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-12);
}

.field {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
  margin: 0;
  padding: 0;
  border: 0;
  min-width: 0;
}

.field > .xp-type-label,
legend {
  color: var(--xp-color-text-secondary);
  padding: 0;
  margin-bottom: var(--xp-space-4);
}

.choice {
  display: inline-flex;
  align-items: center;
  gap: var(--xp-space-4);
  margin-right: var(--xp-space-12);
}

.bumps {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-4);
}

.version {
  width: 12ch;
}

.input {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-2);
  margin-bottom: var(--xp-space-8);
}

.invalid {
  color: var(--xp-color-negative-default);
  margin: 0;
}

.preview ul {
  margin: 0 0 var(--xp-space-8);
  padding-left: var(--xp-space-16);
}

.stage h3 {
  margin: var(--xp-space-8) 0 var(--xp-space-2);
}

.attention {
  color: var(--xp-color-status-attention-on-container);
}

.skipped .blocks {
  color: var(--xp-color-negative-default);
}

.buttons {
  display: flex;
  justify-content: flex-end;
  gap: var(--xp-space-8);
}

.buttons .button {
  color: var(--xp-color-text-primary);
}
</style>
