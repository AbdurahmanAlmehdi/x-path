import { defineStore } from 'pinia'
import { computed, ref, shallowRef } from 'vue'

import {
  api,
  ApiFailure,
  dataOf,
  failureMessage,
  type Workflow,
  type WorkflowIssue,
  type WorkflowSchema,
  type WorkflowSummary,
  type WorkflowTemplate,
} from '@/api/client'

import { emptyDocument, emptyJob, emptyStep, parseWorkflow, toYaml, type WorkflowDocument } from '../document'
import { within, type WorkflowSelection } from '../edits'

/** What the engine said of the YAML. */
export type Validation = 'idle' | 'checking' | 'valid' | 'invalid' | 'unavailable'

/** How long the YAML stays still before the engine checks it. Tests set it to 0. */
export const timing = { validateAfterMs: 400 }

/** The document a new workflow starts from when the engine has no templates: one stage, one job, one step. */
export const draftTemplate: WorkflowDocument = {
  ...emptyDocument(),
  name: 'New workflow',
  stages: [{ name: 'build', jobs: [{ ...emptyJob('build'), steps: [emptyStep('git.checkout')] }] }],
}

/** A line of the YAML to show, each time anew (`seq` changes). */
export interface Reveal {
  line: number
  column: number
  seq: number
}

/**
 * The workflow builder of one project, as the Mac app's: the visual editor
 * and the YAML editor edit one document. The YAML is the one source of
 * truth: it is what is saved and what the engine checks. A visual edit
 * writes the model back as YAML; typing in the YAML reads it into the model
 * when it can, and the visual editor waits while it cannot.
 *
 * Built-in workflows are read-only (the engine answers `409`): "Copy to
 * edit" saves their YAML as a new workflow based on them.
 */
export const useWorkflowBuilderStore = defineStore('workflowBuilder', () => {
  const projectId = ref<string | null>(null)
  /** Whether the list of workflows arrived. */
  const loaded = ref(false)
  const workflows = ref<WorkflowSummary[]>([])
  /** What a document may name, for the pickers; `null` while the engine cannot give it. */
  const schema = ref<WorkflowSchema | null>(null)
  /** The documents a new workflow can start from; empty while the engine cannot give them. */
  const templates = ref<WorkflowTemplate[]>([])
  /** The saved workflow being edited; `null` for a draft. */
  const workflow = ref<Workflow | null>(null)
  /** The name a draft is offered when it is saved (a template's). */
  const draftName = ref<string | null>(null)
  /** The YAML being edited. */
  const yaml = ref('')
  /** The YAML as last saved (empty for a draft). */
  const savedYaml = ref('')
  /** [yaml] read into the model; the last good reading while [shapeIssues] say it cannot be read. */
  const document = shallowRef<WorkflowDocument | null>(null)
  /** What keeps [yaml] from being read into the model, with lines. */
  const shapeIssues = ref<WorkflowIssue[]>([])
  /** The issues the engine found in [yaml], with lines. */
  const engineIssues = ref<WorkflowIssue[]>([])
  const validation = ref<Validation>('idle')
  const selection = ref<WorkflowSelection>({})
  const busy = ref<'loading' | 'saving' | null>(null)
  /** Something that went well, said once. */
  const notice = ref<string | null>(null)
  const error = ref<string | null>(null)
  /** The line the YAML editor shows next: a picked issue, or the first one of a refused save. */
  const reveal = ref<Reveal | null>(null)

  let check = 0
  let timer: ReturnType<typeof setTimeout> | undefined

  const dirty = computed(() => yaml.value !== savedYaml.value)
  const builtin = computed(() => workflow.value?.builtin === true)
  /** Whether saving makes a new workflow (and so needs a name). */
  const savesAsNew = computed(() => workflow.value === null || builtin.value)
  /** Whether the visual editor can edit: the YAML reads as a workflow, and it is not a built-in. */
  const editable = computed(() => document.value !== null && shapeIssues.value.length === 0 && !builtin.value)
  /** What the open workflow is called: its name, the draft's, or `null`. */
  const name = computed(() => workflow.value?.name ?? draftName.value)
  /** Every issue, the model's and the engine's, once each, by place. */
  const issues = computed(() => {
    const seen = new Set<string>()
    return [...shapeIssues.value, ...engineIssues.value]
      .filter((issue) => {
        const key = `${issue.line}:${issue.column}:${issue.message}`
        if (seen.has(key)) return false
        seen.add(key)
        return true
      })
      .sort((a, b) => a.line - b.line || a.column - b.column)
  })

  /** Opens the builder on [id]'s workflows: [workflowId], else the first of its own, else the first, else a draft. */
  async function start(id: string, workflowId?: string): Promise<void> {
    stop()
    projectId.value = id
    loaded.value = false
    workflows.value = []
    workflow.value = null
    yaml.value = ''
    savedYaml.value = ''
    document.value = null
    shapeIssues.value = []
    engineIssues.value = []
    validation.value = 'idle'
    notice.value = null
    error.value = null
    busy.value = 'loading'
    try {
      workflows.value = (await dataOf(api.GET('/projects/{id}/workflows', { params: { path: { id } } }))).workflows
      loaded.value = true
      ;[schema.value, templates.value] = await Promise.all([loadSchema(), loadTemplates()])
      const first =
        workflowId ?? workflows.value.find((each) => !each.builtin)?.id ?? workflows.value[0]?.id
      if (first === undefined) {
        busy.value = null
        draft()
        return
      }
      await read(first)
    } catch (failure) {
      loaded.value = true
      busy.value = null
      error.value = failureMessage(failure)
    }
  }

  async function loadSchema(): Promise<WorkflowSchema | null> {
    try {
      return await dataOf(api.GET('/workflows/schema'))
    } catch {
      return null
    }
  }

  async function loadTemplates(): Promise<WorkflowTemplate[]> {
    try {
      return (await dataOf(api.GET('/workflows/templates'))).templates
    } catch {
      return []
    }
  }

  /** Opens the newest version of [workflowId]. */
  async function open(workflowId: string): Promise<void> {
    busy.value = 'loading'
    notice.value = null
    error.value = null
    try {
      await read(workflowId)
    } catch (failure) {
      busy.value = null
      error.value = failureMessage(failure)
    }
  }

  async function read(workflowId: string) {
    const opened = await dataOf(
      api.GET('/projects/{id}/workflows/{workflowId}', {
        params: { path: { id: projectId.value!, workflowId } },
      }),
    )
    workflow.value = opened
    draftName.value = null
    savedYaml.value = opened.yaml
    selection.value = {}
    busy.value = null
    readYaml(opened.yaml)
  }

  /** Starts a new, unsaved workflow from [template], or from a blank one. */
  function draft(template: WorkflowTemplate | null = null) {
    workflow.value = null
    draftName.value = template === null || template.id === 'blank' ? null : template.id
    savedYaml.value = ''
    selection.value = {}
    notice.value = null
    error.value = null
    readYaml(template?.yaml ?? toYaml(draftTemplate))
  }

  /** What was typed in the YAML editor. */
  function setYaml(text: string) {
    if (text === yaml.value || builtin.value) return
    notice.value = null
    readYaml(text)
  }

  /** A change made in the visual editor, and what to select after it (the current selection by default). */
  function edit(next: WorkflowDocument, select?: WorkflowSelection) {
    if (!editable.value) return
    notice.value = null
    yaml.value = toYaml(next)
    document.value = next
    shapeIssues.value = []
    selection.value = within(select ?? selection.value, next)
    validate()
  }

  /** Shows [next] in the inspector. */
  function select(next: WorkflowSelection) {
    selection.value = document.value === null ? next : within(next, document.value)
  }

  /** [text] as the YAML, read into the model if it can be, and sent to the engine to check. */
  function readYaml(text: string) {
    yaml.value = text
    const parsed = parseWorkflow(text)
    if (parsed.document === null) {
      shapeIssues.value = parsed.issues
    } else {
      document.value = parsed.document
      shapeIssues.value = []
      selection.value = within(selection.value, parsed.document)
    }
    validate()
  }

  /** Has the engine check the YAML once it stays still; a newer check replaces an older one. */
  function validate() {
    validation.value = 'checking'
    clearTimeout(timer)
    const mine = ++check
    timer = setTimeout(async () => {
      const text = yaml.value
      try {
        const result = await dataOf(
          api.POST('/projects/{id}/workflows/validate', {
            params: { path: { id: projectId.value! } },
            body: { yaml: text },
          }),
        )
        if (mine !== check) return
        engineIssues.value = result.issues
        validation.value = result.valid ? 'valid' : 'invalid'
      } catch {
        // The issues the engine found last stay: the document did not get
        // better because the engine went away.
        if (mine === check) validation.value = 'unavailable'
      }
    }, timing.validateAfterMs)
  }

  /** Shows the line of [issue] in the YAML editor. */
  function revealIssue(issue: Pick<WorkflowIssue, 'line' | 'column'>) {
    reveal.value = { line: issue.line, column: issue.column, seq: (reveal.value?.seq ?? 0) + 1 }
  }

  /** Saves the YAML as a new version of the open workflow of the project's own. `true` when the engine took it. */
  function save(): Promise<boolean> {
    const current = workflow.value
    if (current === null || current.builtin) return Promise.resolve(false)
    return saving(() =>
      dataOf(
        api.PUT('/projects/{id}/workflows/{workflowId}', {
          params: { path: { id: projectId.value!, workflowId: current.id } },
          body: { yaml: yaml.value },
        }),
      ),
    )
  }

  /**
   * Saves the YAML as a new workflow called [newName]: a draft, or a copy of
   * a built-in, based on it so the app can say when the built-in changes.
   */
  function saveAs(newName: string): Promise<boolean> {
    const current = workflow.value
    const basedOn = current?.builtin
      ? { builtin: current.name, version: current.version.version }
      : current?.basedOn
    return saving(() =>
      dataOf(
        api.POST('/projects/{id}/workflows', {
          params: { path: { id: projectId.value! } },
          body: { name: newName, yaml: yaml.value, ...(basedOn ? { basedOn } : {}) },
        }),
      ),
    )
  }

  async function saving(send: () => Promise<Workflow>): Promise<boolean> {
    const checkAtSend = check
    busy.value = 'saving'
    notice.value = null
    error.value = null
    let saved: Workflow
    try {
      saved = await send()
    } catch (failure) {
      busy.value = null
      error.value = failureMessage(failure)
      // The issues are of the YAML sent. A check started before the save is
      // older than them, so it is dropped; once the YAML changed, its own
      // check has the say instead.
      if (failure instanceof ApiFailure && failure.issues.length > 0 && check === checkAtSend) {
        stop()
        engineIssues.value = failure.issues
        validation.value = 'invalid'
        revealIssue(issues.value[0]!)
      }
      return false
    }
    // What was typed while the engine saved stays, unsaved.
    workflow.value = saved
    draftName.value = null
    savedYaml.value = saved.yaml
    notice.value = `Saved ${saved.name}, version ${saved.version.version}.`
    try {
      workflows.value = (
        await dataOf(api.GET('/projects/{id}/workflows', { params: { path: { id: projectId.value! } } }))
      ).workflows
    } catch {
      // The list shows the new workflow the next time it is read.
    }
    busy.value = null
    return true
  }

  /** Stops checking: the builder is gone. */
  function stop() {
    clearTimeout(timer)
    check++
  }

  return {
    projectId,
    loaded,
    workflows,
    schema,
    templates,
    workflow,
    draftName,
    yaml,
    savedYaml,
    document,
    shapeIssues,
    engineIssues,
    validation,
    selection,
    busy,
    notice,
    error,
    reveal,
    dirty,
    builtin,
    savesAsNew,
    editable,
    name,
    issues,
    start,
    open,
    draft,
    setYaml,
    edit,
    select,
    revealIssue,
    save,
    saveAs,
    stop,
  }
})
