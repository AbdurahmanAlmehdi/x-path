import { expect, type Page, test } from '@playwright/test'

import { createPerson, fixtureRepository, signInCode } from './engine'

// The specs of this file build on each other: one project, a copy of a
// built-in that the builder then edits.
test.describe.configure({ mode: 'serial' })

let developer: string
let viewer: string
let projectId: string

async function signIn(page: Page, name: string) {
  await page.goto(`/sign-in#code=${signInCode(name)}`)
  await expect(page.getByTestId('person-name')).toHaveText(name)
}

/** Calls the API as the browser's session does: with the cookie, the Origin and the CSRF header. */
async function call(page: Page, method: string, path: string, body?: unknown) {
  return page.evaluate(
    async ([method, path, body]) => {
      const response = await fetch(`/api/v1${path}`, {
        method,
        headers: { 'content-type': 'application/json', 'x-xpath-csrf': '1' },
        body: body === undefined ? undefined : JSON.stringify(body),
      })
      return { status: response.status, body: await response.json() }
    },
    [method, path, body] as const,
  )
}

/**
 * Records every Content-Security-Policy violation of [page] in
 * `window.cspViolations`, from before any script of the dashboard runs.
 */
async function recordCspViolations(page: Page) {
  await page.addInitScript(() => {
    const seen: string[] = []
    ;(window as unknown as { cspViolations: string[] }).cspViolations = seen
    document.addEventListener('securitypolicyviolation', (event) => {
      seen.push(`${event.violatedDirective} ${event.blockedURI} ${event.sourceFile}:${event.lineNumber}`)
    })
  })
}

function cspViolations(page: Page): Promise<string[]> {
  return page.evaluate(() => (window as unknown as { cspViolations: string[] }).cspViolations)
}

const editor = (page: Page) => page.getByTestId('yaml-editor')

/** Replaces the whole YAML with [text], as if typed (no auto-indent). */
async function typeYaml(page: Page, text: string) {
  await editor(page).click()
  await page.keyboard.press('ControlOrMeta+a')
  await page.keyboard.insertText(text)
}

test.beforeAll(async ({ browser }, testInfo) => {
  developer = `Dev workflows ${testInfo.project.name}`
  viewer = `Viewer workflows ${testInfo.project.name}`
  createPerson(developer, 'developer')
  createPerson(viewer, 'viewer')

  const page = await browser.newPage({ baseURL: testInfo.project.use.baseURL })
  await signIn(page, developer)
  const added = await call(page, 'POST', '/projects', { path: fixtureRepository(`workflows-${testInfo.project.name}`) })
  expect(added.status).toBe(201)
  projectId = added.body.id
  await page.close()
})

test('CodeMirror is not in the entry chunk, and loads with the builder', async ({ page, request }) => {
  // The entry and everything the page preloads with it.
  const html = await (await request.get('/', { headers: { accept: 'text/html' } })).text()
  const entry = [...html.matchAll(/(?:src|href)="(\/assets\/[^"]+\.js)"/g)].map((match) => match[1]!)
  expect(entry.length).toBeGreaterThan(0)
  for (const path of entry) {
    const body = await (await request.get(path)).text()
    expect(body, path).not.toContain('cm-content')
  }

  const scripts: string[] = []
  page.on('response', async (response) => {
    if (response.url().endsWith('.js')) scripts.push(await response.text())
  })
  await signIn(page, developer)
  await page.goto(`/projects/${projectId}`)
  await expect(page.getByRole('link', { name: 'Workflows' })).toBeVisible()
  expect(scripts.some((body) => body.includes('cm-content'))).toBe(false)

  await page.getByRole('link', { name: 'Workflows' }).click()
  await expect(editor(page)).toBeVisible()
  await expect.poll(() => scripts.some((body) => body.includes('cm-content'))).toBe(true)
})

test('the YAML editor renders under the CSP with no violation', async ({ page }) => {
  await recordCspViolations(page)
  await signIn(page, developer)
  const response = await page.goto(`/projects/${projectId}/workflows`)
  expect(response?.headers()['content-security-policy']).toContain("style-src 'self';")
  expect(response?.headers()['content-security-policy']).not.toContain('unsafe')

  await expect(editor(page)).toContainText('schema: 1')
  // CodeMirror's own styles applied: its gutters are a flex row.
  await expect(page.locator('.cm-gutters')).toHaveCSS('display', 'flex')
  await expect(page.getByTestId('validation')).toHaveText('Valid')
  expect(await cspViolations(page)).toEqual([])
})

test('a built-in workflow is read-only, and Copy to edit makes one of your own', async ({ page }) => {
  await signIn(page, developer)
  await page.goto(`/projects/${projectId}/workflows`)
  await page.getByRole('combobox', { name: 'Workflow' }).selectOption({ label: 'dev-build' })

  await expect(page.getByTestId('workflow-subtitle')).toContainText('dev-build · Version 1 · Built-in')
  await expect(page.getByTestId('builtin-hint')).toBeVisible()
  await expect(editor(page)).toHaveAttribute('contenteditable', 'false')
  await expect(page.getByRole('button', { name: 'Save', exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Add stage' })).toBeDisabled()
  // The engine decides: a built-in answers 409.
  const builtin = (await call(page, 'GET', `/projects/${projectId}/workflows`)).body.workflows.find(
    (each: { name: string }) => each.name === 'dev-build',
  )
  const refused = await call(page, 'PUT', `/projects/${projectId}/workflows/${builtin.id}`, { yaml: 'schema: 1' })
  expect(refused.status).toBe(409)

  await page.getByRole('button', { name: 'Copy to edit' }).click()
  const dialog = page.getByRole('dialog', { name: 'Copy dev-build to edit' })
  await expect(dialog.getByRole('textbox', { name: 'Name' })).toHaveValue('dev-build-copy')
  await dialog.getByRole('button', { name: 'Copy' }).click()

  await expect(page.getByRole('status').filter({ hasText: 'Saved dev-build-copy, version 1.' })).toBeVisible()
  await expect(page.getByTestId('workflow-subtitle')).toHaveText('dev-build-copy · Version 1')
  await expect(page).toHaveURL(/\/workflows\/wf_/)
  await expect(editor(page)).toHaveAttribute('contenteditable', 'true')
  const copy = await call(page, 'GET', `/projects/${projectId}/workflows`)
  expect(copy.body.workflows.find((each: { name: string }) => each.name === 'dev-build-copy').basedOn).toEqual({
    builtin: 'dev-build',
    version: 1,
  })
})

test('a step added in the visual view shows up in the YAML, and the reverse', async ({ page }) => {
  await signIn(page, developer)
  await page.goto(`/projects/${projectId}/workflows`)
  await page.getByRole('combobox', { name: 'Workflow' }).selectOption({ label: 'dev-build-copy' })
  await expect(page.getByTestId('workflow-subtitle')).toHaveText('dev-build-copy · Version 1')

  // Visual → YAML.
  await page.locator('[data-job="upload"]').click()
  await page.getByRole('combobox', { name: 'Add step' }).selectOption('command')
  await expect(page.getByTestId('job-fields').locator('summary').last()).toContainText('command')
  await expect(editor(page)).toContainText('- kind: command')
  await expect(page.getByTestId('workflow-subtitle')).toContainText('Unsaved changes')

  // YAML → visual.
  await typeYaml(
    page,
    `schema: 1
name: Typed
stages:
  - name: only
    jobs:
      typed-job:
        steps:
          - kind: git.checkout
`,
  )
  await expect(page.locator('[data-job="typed-job"]')).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Pipeline' })).toContainText('Typed')
  await expect(page.locator('[data-job="upload"]')).toHaveCount(0)
  await expect(page.getByTestId('validation')).toHaveText('Valid')

  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page.getByRole('status').filter({ hasText: 'Saved dev-build-copy, version 2.' })).toBeVisible()
  await expect(page.getByTestId('workflow-subtitle')).toHaveText('dev-build-copy · Version 2')
})

test("saving invalid YAML shows the validator's line and message, with the cursor on that line", async ({
  page,
}) => {
  await signIn(page, developer)
  await page.goto(`/projects/${projectId}/workflows`)
  await page.getByRole('combobox', { name: 'Workflow' }).selectOption({ label: 'dev-build-copy' })
  await expect(page.getByTestId('workflow-subtitle')).toHaveText('dev-build-copy · Version 2')

  // Line 8 names a step type the engine does not have; the document still
  // reads as a workflow, so only the engine finds it.
  await typeYaml(
    page,
    `schema: 1
name: Typed
stages:
  - name: only
    jobs:
      typed-job:
        steps:
          - kind: no.such.step
`,
  )
  await page.getByRole('button', { name: 'Save', exact: true }).click()

  await expect(page.getByRole('alert')).toBeVisible()
  const issue = page.getByRole('list', { name: 'Issues' }).getByRole('button').first()
  await expect(issue).toContainText('Line 8')
  await expect(issue).toContainText('no.such.step')
  await expect(page.locator('.cm-lineNumbers .cm-activeLineGutter')).toHaveText('8')
  await expect(page.locator('.cm-activeLine')).toHaveText('          - kind: no.such.step')
  await expect(page.locator('.cm-lint-marker-error')).toHaveCount(1)
  await expect(page.getByTestId('workflow-subtitle')).toContainText('Unsaved changes')

  // Leaving asks first; Keep editing stays.
  await page.getByRole('link', { name: 'Runs', exact: true }).click()
  const discard = page.getByRole('dialog', { name: 'Discard unsaved changes?' })
  await discard.getByRole('button', { name: 'Keep editing' }).click()
  await expect(page).toHaveURL(/\/workflows\//)
})

test('a viewer reads workflows with nothing to change them', async ({ page }) => {
  await signIn(page, viewer)
  await page.goto(`/projects/${projectId}/workflows`)

  await expect(page.getByTestId('workflow-subtitle')).toContainText('dev-build-copy · Version 2')
  await expect(editor(page)).toHaveAttribute('contenteditable', 'false')
  await expect(page.getByRole('button', { name: 'New' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: /^Save/ })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Add stage' })).toBeDisabled()
})
