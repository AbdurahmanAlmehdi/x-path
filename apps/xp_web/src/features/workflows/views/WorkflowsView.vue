<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter, type RouteLocationNormalized } from 'vue-router'

import type { WorkflowTemplate } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import Dialog from '@/ui/Dialog.vue'

import WorkflowGraph from '../components/WorkflowGraph.vue'
import WorkflowInspector from '../components/WorkflowInspector.vue'
import YamlEditor from '../components/YamlEditor.vue'
import { copyName, nameProblem, validationLabel } from '../labels'
import { useWorkflowBuilderStore } from '../stores/builder'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const store = useWorkflowBuilderStore()

const projectId = computed(() => String(route.params.id))
const routeWorkflowId = computed(() => workflowIdOf(route))
/** Creating, saving and changing workflows needs `develop`; the engine still decides. */
const canEdit = computed(() => session.can('develop'))
const busy = computed(() => store.busy !== null)

function workflowIdOf(location: Pick<RouteLocationNormalized, 'params'>): string | undefined {
  const id = location.params.workflowId
  return typeof id === 'string' && id !== '' ? id : undefined
}

watch(projectId, (id) => void store.start(id, routeWorkflowId.value), { immediate: true })
watch(routeWorkflowId, (id) => {
  if (id !== undefined && id !== store.workflow?.id) void store.open(id)
})
// The address follows the open workflow: the first one opened, a saved draft, a copy.
watch(
  () => store.workflow?.id,
  (id) => {
    if (store.busy === 'loading' || id === routeWorkflowId.value) return
    void router.replace({
      name: 'workflows',
      params: id === undefined ? { id: projectId.value } : { id: projectId.value, workflowId: id },
    })
  },
)

const subtitle = computed(() => {
  const workflow = store.workflow
  return [
    store.name,
    workflow ? `Version ${workflow.version.version}` : 'Not saved yet',
    workflow?.builtin ? 'Built-in' : null,
    workflow && store.dirty ? 'Unsaved changes' : null,
  ]
    .filter((part) => part !== null)
    .join(' · ')
})
const status = computed(() => validationLabel(store.validation, store.issues.length))
const taken = computed(() => store.workflows.map((each) => each.name))

// ------------------------------------------------------- leaving unsaved

/** Answers the "Discard unsaved changes?" dialog while it is open. */
const discarding = ref<((discard: boolean) => void) | null>(null)

function confirmDiscard(): Promise<boolean> {
  if (!store.dirty || !canEdit.value) return Promise.resolve(true)
  return new Promise((resolve) => {
    discarding.value = (discard) => {
      discarding.value = null
      resolve(discard)
    }
  })
}

onBeforeRouteLeave(() => confirmDiscard())
onBeforeRouteUpdate((to) => {
  // The address catching up with the builder asks nothing.
  if (String(to.params.id) === store.projectId && workflowIdOf(to) === store.workflow?.id) return true
  return confirmDiscard()
})

function onBeforeUnload(event: BeforeUnloadEvent) {
  if (store.dirty && canEdit.value) event.preventDefault()
}

function onKeydown(event: KeyboardEvent) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') {
    event.preventDefault()
    if (canSave.value) save()
  }
}

onMounted(() => {
  window.addEventListener('beforeunload', onBeforeUnload)
  window.addEventListener('keydown', onKeydown)
})
onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', onBeforeUnload)
  window.removeEventListener('keydown', onKeydown)
  discarding.value?.(false)
  store.stop()
})

// --------------------------------------------------------------- commands

function pick(event: Event) {
  const id = (event.target as HTMLSelectElement).value
  if (id === '' || id === store.workflow?.id) return
  void router.push({ name: 'workflows', params: { id: projectId.value, workflowId: id } }).then(() => {
    // Kept editing: the menu shows the open workflow again.
    ;(event.target as HTMLSelectElement).value = store.workflow?.id ?? ''
  })
}

/** Whether the template picker is open. */
const picking = ref(false)

async function startNew() {
  if (!(await confirmDiscard())) return
  if (store.templates.length > 0) picking.value = true
  else store.draft()
}

function startFrom(template: WorkflowTemplate) {
  picking.value = false
  store.draft(template)
}

/** The name dialog: for a draft, or a copy of a built-in. */
const naming = ref(false)
const newName = ref('')
const problem = computed(() => (newName.value === '' ? null : nameProblem(newName.value, taken.value)))

const canSave = computed(
  () => canEdit.value && !busy.value && store.loaded && (store.savesAsNew || store.dirty),
)

function save() {
  if (!store.savesAsNew) {
    void store.save()
    return
  }
  const workflow = store.workflow
  newName.value = store.draftName ?? (workflow ? copyName(workflow.name, taken.value) : '')
  naming.value = true
}

async function saveAs() {
  if (newName.value === '' || problem.value !== null) return
  naming.value = false
  await store.saveAs(newName.value)
}
</script>

<template>
  <section class="workflows">
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Workflows</h1>
        <p class="muted" data-testid="workflow-subtitle">{{ store.loaded ? subtitle : '' }}</p>
      </div>
      <div class="actions">
        <select
          v-if="store.workflows.length > 0"
          aria-label="Workflow"
          class="mono"
          :value="store.workflow?.id ?? ''"
          :disabled="busy"
          @change="pick"
        >
          <option v-if="!store.workflow" value="">{{ store.name ?? 'Not saved yet' }}</option>
          <option v-for="workflow in store.workflows" :key="workflow.id" :value="workflow.id">
            {{ workflow.archivedAt ? `${workflow.name} (archived)` : workflow.name }}
          </option>
        </select>
        <button v-if="canEdit" type="button" :disabled="busy" @click="startNew">New</button>
        <RouterLink
          v-if="canEdit && store.workflow && !store.dirty && !store.workflow.archivedAt"
          :to="{ name: 'dispatch', params: { id: projectId }, query: { workflow: store.workflow.id } }"
          class="button"
        >
          Run…
        </RouterLink>
        <button
          v-if="canEdit && store.builtin"
          type="button"
          class="primary"
          :disabled="!canSave"
          @click="save"
        >
          Copy to edit
        </button>
        <button v-else-if="canEdit" type="button" class="primary" :disabled="!canSave" @click="save">
          {{ store.savesAsNew ? 'Save as…' : 'Save' }}
        </button>
      </div>
    </header>

    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="store.notice" class="notice" role="status">{{ store.notice }}</p>
    <p v-if="store.builtin" class="notice" data-testid="builtin-hint">
      Built-in workflows cannot be changed.
      <template v-if="canEdit">Copy to edit makes a workflow of your own from it.</template>
    </p>
    <p v-if="store.workflow?.archivedAt" class="notice">
      Archived: kept with its versions and runs, and not offered to dispatch.
    </p>
    <p v-if="!canEdit && store.loaded" class="muted">Your role can read workflows; changing them takes a developer.</p>

    <p v-if="!store.loaded" class="muted">Loading…</p>
    <div v-else class="builder">
      <div class="visual">
        <p v-if="store.shapeIssues.length > 0" class="notice" data-testid="shape-locked">
          The visual editor waits until the YAML reads as a workflow. Fix the issues in the YAML.
        </p>
        <template v-if="store.document">
          <WorkflowGraph
            :document="store.document"
            :selection="store.selection"
            :disabled="!store.editable || !canEdit || busy"
            @select="store.select"
            @edit="store.edit"
          />
          <WorkflowInspector
            :document="store.document"
            :selection="store.selection"
            :schema="store.schema"
            :disabled="!store.editable || !canEdit || busy"
            @edit="store.edit"
          />
        </template>
      </div>
      <section class="yaml" aria-label="YAML">
        <header class="yaml-head">
          <h2 class="xp-type-title">YAML</h2>
          <span class="muted" role="status" data-testid="validation">{{ status }}</span>
        </header>
        <YamlEditor
          :text="store.yaml"
          :read-only="store.builtin || !canEdit"
          :issues="store.issues"
          :reveal="store.reveal"
          @change="store.setYaml"
        />
        <ol v-if="store.issues.length > 0" class="issues" aria-label="Issues">
          <li v-for="issue in store.issues" :key="`${issue.line}:${issue.column}:${issue.message}`">
            <button type="button" class="issue" @click="store.revealIssue(issue)">
              <span class="mono">Line {{ issue.line }}</span>
              <span>{{ issue.hint ? `${issue.message} ${issue.hint}` : issue.message }}</span>
            </button>
          </li>
        </ol>
      </section>
    </div>

    <Dialog v-if="picking" title="Start a new workflow" @close="picking = false">
      <ul class="templates">
        <li v-for="template in store.templates" :key="template.id">
          <button type="button" class="template" @click="startFrom(template)">
            <strong>{{ template.title }}</strong>
            <span class="muted">{{ template.description }}</span>
          </button>
        </li>
      </ul>
      <template #footer>
        <button type="button" @click="picking = false">Cancel</button>
      </template>
    </Dialog>

    <Dialog
      v-if="naming"
      :title="store.builtin ? `Copy ${store.workflow?.name} to edit` : 'Save as a new workflow'"
      @close="naming = false"
    >
      <form class="form" @submit.prevent="saveAs">
        <label class="field">
          <span class="xp-type-label">Name</span>
          <input v-model.trim="newName" type="text" class="mono" autocomplete="off" spellcheck="false" />
        </label>
        <p class="muted">Letters, digits, dots, dashes and underscores; unique in the project.</p>
        <p v-if="problem" class="alert" role="alert">{{ problem }}</p>
      </form>
      <template #footer>
        <button type="button" @click="naming = false">Cancel</button>
        <button type="button" class="primary" :disabled="newName === '' || problem !== null" @click="saveAs">
          {{ store.builtin ? 'Copy' : 'Save' }}
        </button>
      </template>
    </Dialog>

    <Dialog v-if="discarding" title="Discard unsaved changes?" @close="discarding(false)">
      <p>The changes to {{ store.name ?? 'the workflow' }} are not saved.</p>
      <template #footer>
        <button type="button" @click="discarding(false)">Keep editing</button>
        <button type="button" class="danger" @click="discarding(true)">Discard</button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.builder {
  display: grid;
  grid-template-columns: minmax(0, 5fr) minmax(0, 4fr);
  gap: var(--xp-space-16);
  align-items: start;
}

@media (max-width: 960px) {
  .builder {
    grid-template-columns: minmax(0, 1fr);
  }
}

.visual {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-16);
  min-width: 0;
}

.yaml {
  min-width: 0;
}

.yaml-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--xp-space-8);
}

.issues,
.templates {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
  margin: var(--xp-space-8) 0 0;
  padding: 0;
  list-style: none;
}

.issue,
.template {
  display: flex;
  gap: var(--xp-space-8);
  width: 100%;
  height: auto;
  padding: var(--xp-space-6) var(--xp-space-8);
  font: var(--xp-type-body);
  text-align: left;
}

.issue {
  color: var(--xp-color-status-negative-on-container);
  background: var(--xp-color-status-negative-container);
  border-color: transparent;
}

.issue .mono {
  flex: none;
}

.template {
  flex-direction: column;
}
</style>
