import { flushPromises, type DOMWrapper, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Router } from 'vue-router'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { workflowOf, workflowSummaryOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

import { timing, useWorkflowBuilderStore } from '../stores/builder'

const ownYaml = `schema: 1
name: Nightly
stages:
  - name: build
    jobs:
      build:
        matrix:
          platform: \${{ platforms }}
        capabilities: [flutter]
        steps:
          - kind: git.checkout
          - kind: command
            gate: prod_release
            if: platform == 'ios'
            with:
              executable: sh
              mystery: 1
          - kind: future.step
  - name: ship
    jobs:
      ship:
        steps: []
`

const schema = {
  schema: 1,
  steps: [
    {
      kind: 'git.checkout',
      with: [],
      title: 'Check out',
      description: 'Checks out the commit.',
      group: 'Source',
      capabilities: [],
      keys: [],
    },
    {
      kind: 'command',
      with: ['executable'],
      title: 'Command',
      description: 'Runs a program.',
      group: 'Other',
      capabilities: [],
      keys: [
        { name: 'executable', type: 'string', required: true, description: 'The program.' },
        { name: 'quiet', type: 'boolean', required: false, description: 'Less output.', default: false },
        { name: 'shell', type: 'string', required: false, description: 'Which.', options: ['sh', 'bash'] },
        { name: 'checks', type: 'list', required: false, description: 'Which.', options: ['source', 'credentials'] },
      ],
    },
  ],
  gates: ['prod_release', 'push'],
  gateLabels: { prod_release: 'Production release' },
  capabilities: ['flutter', 'android'],
  matrixAxes: ['platform', 'flavor'],
  platforms: ['android', 'ios'],
  variables: [],
}

const own = workflowOf({ id: 'wf_2', name: 'nightly', builtin: false, yaml: ownYaml })
const builtin = workflowOf({ yaml: 'schema: 1\nname: Dev build\nstages: []\n' })
const summaries = [workflowSummaryOf(), workflowSummaryOf({ id: 'wf_2', name: 'nightly', builtin: false })]
const templates = [
  { id: 'blank', title: 'Blank', description: 'Nothing yet.', yaml: 'schema: 1\nstages: []\n' },
  { id: 'tests', title: 'Tests only', description: 'Runs the tests.', yaml: 'schema: 1\nname: Tests\nstages: []\n' },
]

describe('WorkflowsView', () => {
  let app: VueWrapper | undefined
  let router: Router

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
    timing.validateAfterMs = 0
    // jsdom has no execCommand, which CodeMirror reads the selection of a shadow root with,
    // and no layout, which it measures to scroll a line into view.
    Object.defineProperty(document, 'execCommand', { value: () => false, configurable: true })
    Range.prototype.getClientRects ??= () => [] as unknown as DOMRectList
    Range.prototype.getBoundingClientRect ??= () => new DOMRect()
  })
  afterEach(() => {
    app?.unmount()
    timing.validateAfterMs = 400
  })

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, role: 'developer' | 'viewer' = 'developer') {
    return stubEngine({
      'GET /me': { status: 200, body: meOf(role, role === 'viewer' ? [] : ['develop']) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: summaries } },
      'GET /workflows/schema': { status: 200, body: schema },
      'GET /workflows/templates': { status: 200, body: { templates } },
      'GET /projects/prj_1/workflows/wf_1': { status: 200, body: builtin },
      'GET /projects/prj_1/workflows/wf_2': { status: 200, body: own },
      'POST /projects/prj_1/workflows/validate': { status: 200, body: { valid: true, issues: [] } },
      ...routes,
    })
  }

  async function open(path = '/projects/prj_1/workflows') {
    ;({ app, router } = await openApp(path))
    await vi.waitFor(() => expect(useWorkflowBuilderStore().loaded).toBe(true))
    await flushPromises()
  }

  const store = () => useWorkflowBuilderStore()

  function button(label: string, within: DOMWrapper<Element> | VueWrapper = app!) {
    const found = within.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  function editorText(): string {
    const host = app!.find('.yaml-editor > div').element
    return host.shadowRoot?.querySelector('.cm-content')?.textContent ?? ''
  }

  function field(label: string): DOMWrapper<HTMLInputElement> {
    const found = app!.findAll('label.field').find((each) => each.find('.xp-type-label').text() === label)
    if (!found) throw new Error(`No field "${label}".`)
    return found.find('input, textarea') as DOMWrapper<HTMLInputElement>
  }

  async function type(input: DOMWrapper<HTMLInputElement>, text: string) {
    await input.trigger('focus')
    await input.setValue(text)
    await input.trigger('blur')
  }

  it('opens the first workflow of the project’s own in the pipeline and the YAML editor', async () => {
    engine()
    await open()

    expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/workflows/wf_2')
    expect(app!.find('[data-testid="workflow-subtitle"]').text()).toBe('nightly · Version 1')
    expect(app!.find('nav[aria-label="Pipeline"]').text()).toContain('Nightly')
    await vi.waitFor(() => expect(editorText()).toContain('name: Nightly'))
    await vi.waitFor(() => expect(app!.find('[data-testid="validation"]').text()).toBe('Valid'))
    expect(app!.find('a.button[href="/projects/prj_1/dispatch?workflow=wf_2"]').exists()).toBe(true)
  })

  it('edits the workflow, a stage and a job in the visual view, and the YAML follows', async () => {
    engine()
    await open()

    await type(field('Name'), 'Renamed')
    await type(field('Description'), 'Line')
    await app!.find('input[type="checkbox"]').setValue(true)
    expect(store().yaml).toContain('name: Renamed\ndescription: Line\nlock: project\n')
    await vi.waitFor(() => expect(editorText()).toContain('lock: project'))
    expect(app!.find('[data-testid="workflow-subtitle"]').text()).toContain('Unsaved changes')

    await button('ship').trigger('click')
    await type(field('Stage name'), 'deliver')
    await button('Move earlier').trigger('click')
    expect(store().document!.stages.map((stage) => stage.name)).toEqual(['deliver', 'build'])
    await button('Move later').trigger('click')
    await button('Remove stage').trigger('click')
    expect(store().document!.stages.map((stage) => stage.name)).toEqual(['build'])

    await button('Add stage').trigger('click')
    expect(store().document!.stages[1]).toMatchObject({ name: 'stage-2', jobs: [{ id: 'stage-2' }] })
    expect(store().selection).toEqual({ stage: 1, job: 0 })
    await app!.findAll('.add').find((each) => each.text() === 'Add job')!.trigger('click')
    expect(store().document!.stages[0]!.jobs.map((job) => job.id)).toEqual(['build', 'build-2'])
    expect(store().selection).toEqual({ stage: 0, job: 1 })
    await button('Move earlier').trigger('click')
    expect(store().selection).toEqual({ stage: 0, job: 0 })
    await button('Move later').trigger('click')
    await button('Remove job').trigger('click')
    expect(store().document!.stages[0]!.jobs.map((job) => job.id)).toEqual(['build'])
    await button('Renamed').trigger('click')
    expect(app!.find('[data-testid="workflow-fields"]').exists()).toBe(true)
  })

  it('edits a job: its id, name, if, matrix, capabilities and steps', async () => {
    engine()
    await open()
    await app!.find('[data-job="build"]').trigger('click')
    const job = () => store().document!.stages[0]!.jobs[0]!

    await type(field('Job id'), 'compile')
    await type(field('Job name'), 'Compile')
    await type(field('If'), "platform == 'ios'")
    expect(job()).toMatchObject({ id: 'compile', name: 'Compile', condition: "platform == 'ios'" })

    const axis = (name: string) => app!.find(`[data-axis="${name}"]`)
    await axis('platform').find('select').setValue('list')
    expect(job().matrix).toEqual([{ name: 'platform', values: ['android', 'ios'], reference: null }])
    await type(axis('platform').find('input') as DOMWrapper<HTMLInputElement>, 'ios, ')
    expect(job().matrix[0]!.values).toEqual(['ios'])
    await axis('flavor').find('select').setValue('dispatch')
    expect(job().matrix[1]).toEqual({ name: 'flavor', values: null, reference: '${{ flavors }}' })
    expect(axis('flavor').text()).toContain('${{ flavors }}')
    await axis('flavor').find('select').setValue('none')
    expect(job().matrix).toHaveLength(1)

    const android = app!.findAll('.check').find((each) => each.text() === 'android')!
    await android.find('input').setValue(true)
    expect(job().capabilities).toEqual(['flutter', 'android'])
    await android.find('input').setValue(false)
    expect(job().capabilities).toEqual(['flutter'])

    await app!.find('select[aria-label="Add step"]').setValue('command')
    expect(job().steps.map((step) => step.kind)).toEqual(['git.checkout', 'command', 'future.step', 'command'])
    await vi.waitFor(() => expect(editorText()).toContain('- kind: future.step          - kind: command'))
  })

  it('edits a step: its type, gate, if and with values by their type', async () => {
    engine()
    await open()
    await app!.find('[data-job="build"]').trigger('click')
    const step = () => store().document!.stages[0]!.jobs[0]!.steps[1]!
    const editor = () => app!.find('[data-step="1"]')

    expect(editor().find('summary').text()).toContain('Production release')
    expect(editor().text()).toContain('Runs a program.')
    const gate = editor().findAll('select').find((each) => each.find('option').text() === 'No gate')!
    await gate.setValue('push')
    expect(step().gate).toBe('push')
    await gate.setValue('')
    expect(step().gate).toBeNull()
    await type(editor().findAll('input').find((each) => each.attributes('placeholder') === "platform == 'ios'")! as DOMWrapper<HTMLInputElement>, ' ')
    expect(step().condition).toBeNull()

    const withField = (key: string) => editor().find(`[data-key="${key}"]`)
    await type(withField('executable').find('input') as DOMWrapper<HTMLInputElement>, 'bash')
    expect(step().with.executable).toBe('bash')
    await type(withField('executable').find('input') as DOMWrapper<HTMLInputElement>, '')
    expect('executable' in step().with).toBe(false)
    expect(withField('executable').text()).toContain('Needed')

    expect(withField('quiet').find('option').text()).toBe('Default (false)')
    await withField('quiet').find('select').setValue('true')
    expect(step().with.quiet).toBe(true)
    await withField('quiet').find('select').setValue('')
    expect('quiet' in step().with).toBe(false)

    await withField('shell').find('select').setValue('bash')
    expect(step().with.shell).toBe('bash')
    await withField('shell').find('select').setValue('')

    const credentials = withField('checks').findAll('input')[1]!
    await credentials.setValue(true)
    expect(step().with.checks).toEqual(['credentials'])

    await type(withField('mystery').find('input') as DOMWrapper<HTMLInputElement>, '[a, b]')
    expect(step().with.mystery).toEqual(['a', 'b'])

    const kind = editor().find('select.mono')
    await kind.setValue('git.checkout')
    expect(step().kind).toBe('git.checkout')
    expect(app!.find('[data-step="2"] optgroup[label="Other"]').text()).toContain('future.step')

    await button('Move earlier', app!.find('[data-step="2"]')).trigger('click')
    expect(store().document!.stages[0]!.jobs[0]!.steps.map((each) => each.kind)).toEqual([
      'git.checkout',
      'future.step',
      'git.checkout',
    ])
    await button('Move later', app!.find('[data-step="0"]')).trigger('click')
    await button('Remove step', app!.find('[data-step="0"]')).trigger('click')
    expect(store().document!.stages[0]!.jobs[0]!.steps).toHaveLength(2)
  })

  it('takes step types as text while the engine cannot give its schema', async () => {
    engine({ 'GET /workflows/schema': { status: 500, body: errorBody('internal', 'Down.') } })
    await open()
    await app!.find('[data-job="build"]').trigger('click')

    expect(app!.text()).toContain('its step types are not known')
    expect(app!.find('select[aria-label="Add step"]').exists()).toBe(false)
    await type(app!.find('[data-step="0"]').find('input') as DOMWrapper<HTMLInputElement>, 'test ')
    expect(store().document!.stages[0]!.jobs[0]!.steps[0]!.kind).toBe('test')
  })

  it('reads typed YAML, and waits with the visual view while it cannot', async () => {
    engine()
    await open()

    store().setYaml('schema: 1\nstages: [\n')
    await flushPromises()

    expect(app!.find('[data-testid="shape-locked"]').exists()).toBe(true)
    expect(button('Add stage').attributes('disabled')).toBeDefined()
    expect(app!.find('ol[aria-label="Issues"]').text()).toMatch(/Line \d+/)
  })

  it("shows the issues of a refused save, and reveals the line of the one picked", async () => {
    const issue = { line: 2, column: 7, message: 'Unknown step type "x".', hint: 'Did you mean "test"?' }
    engine({
      'PUT /projects/prj_1/workflows/wf_2': {
        status: 422,
        body: { error: { code: 'workflow_invalid', message: 'The workflow has 1 issue.', issues: [issue] } },
      },
    })
    await open()
    await vi.waitFor(() => expect(editorText()).toContain('name: Nightly'))
    store().setYaml(`${ownYaml}# changed\n`)
    await flushPromises()

    await button('Save').trigger('click')
    await flushPromises()

    expect(app!.find('[role="alert"]').text()).toBe('The workflow has 1 issue.')
    const picked = app!.find('ol[aria-label="Issues"] button')
    expect(picked.text()).toBe('Line 2Unknown step type "x". Did you mean "test"?')
    await picked.trigger('click')
    expect(store().reveal).toMatchObject({ line: 2, seq: 2 })
  })

  it('saves with Save and with ⌘S', async () => {
    const saved = { ...own, yaml: `${ownYaml}# changed\n`, version: { id: 'wfv_2', version: 2, createdAt: '2026-11-14T10:00:00Z' } }
    const seen = engine({ 'PUT /projects/prj_1/workflows/wf_2': { status: 200, body: saved } })
    await open()
    expect(button('Save').attributes('disabled')).toBeDefined()

    store().setYaml(`${ownYaml}# changed\n`)
    await flushPromises()
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 's', metaKey: true }))
    await flushPromises()

    expect(seen.filter((request) => request.method === 'PUT')).toHaveLength(1)
    expect(app!.find('[role="status"].notice').text()).toBe('Saved nightly, version 2.')
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'x', ctrlKey: true }))
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 's', ctrlKey: true }))
    await flushPromises()
    expect(seen.filter((request) => request.method === 'PUT')).toHaveLength(1)
  })

  it('shows a built-in read-only, and copies it to edit under a free name', async () => {
    const copy = workflowOf({ id: 'wf_3', name: 'dev-build-copy', builtin: false, yaml: builtin.yaml })
    const seen = engine({ 'POST /projects/prj_1/workflows': { status: 201, body: copy } })
    await open('/projects/prj_1/workflows/wf_1')

    expect(app!.find('[data-testid="builtin-hint"]').text()).toContain('Copy to edit makes a workflow of your own')
    expect(app!.find('[data-testid="workflow-subtitle"]').text()).toBe('dev-build · Version 1 · Built-in')
    expect(app!.findAll('button').some((each) => each.text() === 'Save')).toBe(false)

    await button('Copy to edit').trigger('click')
    const dialog = () => app!.find('[role="dialog"]')
    expect(dialog().attributes('aria-label')).toBe('Copy dev-build to edit')
    const name = dialog().find('input')
    expect((name.element as HTMLInputElement).value).toBe('dev-build-copy')
    await name.setValue('nightly')
    expect(dialog().find('[role="alert"]').text()).toBe('The project already has a workflow called nightly.')
    await dialog().find('form').trigger('submit')
    expect(dialog().exists()).toBe(true)
    await name.setValue('dev-build-copy')
    await button('Copy', dialog()).trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.method === 'POST' && request.path === '/projects/prj_1/workflows')?.body).toMatchObject({
      name: 'dev-build-copy',
      basedOn: { builtin: 'dev-build', version: 1 },
    })
    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/workflows/wf_3'))
  })

  it('starts a new workflow from a template and saves it under a name', async () => {
    const created = workflowOf({ id: 'wf_4', name: 'tests', builtin: false, yaml: templates[1]!.yaml })
    engine({ 'POST /projects/prj_1/workflows': { status: 201, body: created } })
    await open()

    await button('New').trigger('click')
    expect(app!.find('[role="dialog"]').attributes('aria-label')).toBe('Start a new workflow')
    await button('Cancel', app!.find('[role="dialog"]')).trigger('click')
    await button('New').trigger('click')
    await app!.findAll('.template')[1]!.trigger('click')
    await flushPromises()

    expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/workflows')
    expect(app!.find('[data-testid="workflow-subtitle"]').text()).toBe('tests · Not saved yet')
    expect(app!.find('select[aria-label="Workflow"] option').text()).toBe('tests')

    await button('Save as…').trigger('click')
    const dialog = app!.find('[role="dialog"]')
    expect(dialog.attributes('aria-label')).toBe('Save as a new workflow')
    expect((dialog.find('input').element as HTMLInputElement).value).toBe('tests')
    await button('Cancel', dialog).trigger('click')
    await button('Save as…').trigger('click')
    await app!.find('[role="dialog"] form').trigger('submit')
    await flushPromises()

    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/workflows/wf_4'))
    expect(app!.find('[data-testid="workflow-subtitle"]').text()).toBe('tests · Version 1')
  })

  it('starts a blank draft when the engine has no templates', async () => {
    engine({ 'GET /workflows/templates': { status: 500, body: errorBody('internal', 'Down.') } })
    await open()

    await button('New').trigger('click')

    expect(store().document?.name).toBe('New workflow')
    expect(app!.find('[role="dialog"]').exists()).toBe(false)
  })

  it('asks before leaving unsaved changes, and opens another workflow once they go', async () => {
    engine()
    await open()
    store().setYaml(`${ownYaml}# changed\n`)
    await flushPromises()

    await app!.find('select[aria-label="Workflow"]').setValue('wf_1')
    await flushPromises()
    const dialog = () => app!.find('[role="dialog"]')
    expect(dialog().attributes('aria-label')).toBe('Discard unsaved changes?')
    await button('Keep editing', dialog()).trigger('click')
    await flushPromises()
    expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/workflows/wf_2')
    expect((app!.find('select[aria-label="Workflow"]').element as HTMLSelectElement).value).toBe('wf_2')

    const unload = new Event('beforeunload', { cancelable: true })
    window.dispatchEvent(unload)
    expect(unload.defaultPrevented).toBe(true)

    await app!.find('select[aria-label="Workflow"]').setValue('wf_1')
    await flushPromises()
    await button('Discard', dialog()).trigger('click')
    await vi.waitFor(() => expect(store().workflow?.id).toBe('wf_1'))
    expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1/workflows/wf_1')

    const clean = new Event('beforeunload', { cancelable: true })
    window.dispatchEvent(clean)
    expect(clean.defaultPrevented).toBe(false)
  })

  it('says why the workflows could not be read', async () => {
    engine({ 'GET /projects/prj_1/workflows': { status: 404, body: errorBody('not_found', 'No such project.') } })
    await open()

    expect(app!.find('[role="alert"]').text()).toBe('No such project.')
    expect(app!.find('select[aria-label="Workflow"]').exists()).toBe(false)
  })

  it('shows a viewer the workflows with nothing to change them', async () => {
    engine({}, 'viewer')
    await open()

    expect(app!.text()).toContain('Your role can read workflows; changing them takes a developer.')
    expect(app!.findAll('main button').map((each) => each.text())).not.toContain('New')
    expect(app!.findAll('main button').some((each) => each.text().startsWith('Save'))).toBe(false)
    expect(button('Add stage').attributes('disabled')).toBeDefined()
    expect(app!.find('a.button[href*="dispatch"]').exists()).toBe(false)
    store().setYaml(`${ownYaml}# changed\n`)
    await router.push('/projects/prj_1/workflows/wf_1')
    await vi.waitFor(() => expect(store().workflow?.id).toBe('wf_1'))
  })
})
