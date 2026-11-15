import { type Browser, expect, type Page, test } from '@playwright/test'

import { createPerson, fixtureRepository, signInCode } from './engine'

// The specs of this file build on each other: one project, its gated runs.
test.describe.configure({ mode: 'serial' })

let developer: string
let releaser: string
let otherReleaser: string
let projectId: string
let workflowId: string

// A workflow whose only work is behind the production release gate, so a
// run reaches the gate with no toolchain: a checkout, then a command.
const gatedWorkflow = `schema: 1
name: Gated
stages:
  - name: only
    jobs:
      ship:
        name: ship
        steps:
          - kind: git.checkout
          - kind: command
            gate: prod_release
            with:
              executable: sh
              arguments:
                - -c
                - echo shipped
`

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

/** A new page of [browser] signed in as [name]. */
async function pageOf(browser: Browser, baseURL: string | undefined, name: string): Promise<Page> {
  const page = await browser.newPage({ baseURL })
  await signIn(page, name)
  return page
}

/** Dispatches the gated workflow as the developer and waits for its approval; returns the approval. */
async function dispatchToGate(page: Page): Promise<{ id: string; runId: string; jobId: string }> {
  const dispatched = await call(page, 'POST', `/projects/${projectId}/workflows/${workflowId}/dispatch`, {})
  expect(dispatched.status).toBe(202)
  const runId = dispatched.body.id as string
  let approval: { id: string; runId: string; jobId: string } | undefined
  await expect
    .poll(
      async () => {
        const listed = await call(page, 'GET', `/approvals?project=${projectId}&state=pending`)
        approval = listed.body.approvals.find((each: { runId: string }) => each.runId === runId)
        return approval !== undefined
      },
      { timeout: 60_000 },
    )
    .toBe(true)
  return approval!
}

test.beforeAll(async ({ browser }, testInfo) => {
  developer = `Dev approvals ${testInfo.project.name}`
  releaser = `Releaser ${testInfo.project.name}`
  otherReleaser = `Other releaser ${testInfo.project.name}`
  createPerson(developer, 'developer')
  createPerson(releaser, 'releaser')
  createPerson(otherReleaser, 'releaser')

  const page = await pageOf(browser, testInfo.project.use.baseURL, developer)
  const added = await call(page, 'POST', '/projects', {
    path: fixtureRepository(`approvals-${testInfo.project.name}`),
  })
  expect(added.status).toBe(201)
  projectId = added.body.id
  const workflow = await call(page, 'POST', `/projects/${projectId}/workflows`, {
    name: 'gated',
    yaml: gatedWorkflow,
  })
  expect(workflow.status).toBe(201)
  workflowId = workflow.body.id
  await page.close()
})

test('a developer sees the approval, and no Approve button', async ({ page }) => {
  await signIn(page, developer)
  await dispatchToGate(page)

  await page.getByRole('link', { name: /Approvals/ }).click()

  await expect(page.getByTestId('needs-you')).toHaveText('1')
  const detail = page.getByTestId('approval-detail')
  await expect(detail.getByRole('heading', { name: 'Approve the production release' })).toBeVisible()
  await expect(detail.getByText(/waits for this/)).toBeVisible()
  await expect(detail.getByTestId('cannot-decide')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Approve…' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Deny…' })).toHaveCount(0)
})

test('a releaser approves the gate in the browser, the job resumes, and the approval names them', async ({
  page,
}) => {
  await signIn(page, releaser)
  const pending = await call(page, 'GET', `/approvals?project=${projectId}&state=pending`)
  const approval = pending.body.approvals[0] as { id: string; jobId: string }

  await page.goto(`/approvals/${approval.id}`)
  await page.getByRole('button', { name: 'Approve…' }).click()
  const dialog = page.getByRole('dialog', { name: 'Review the approval' })
  await expect(dialog).toBeVisible()
  // Return never approves.
  await page.keyboard.press('Enter')
  const approve = dialog.getByRole('button', { name: 'Approve', exact: true })
  await expect(approve).toBeEnabled()
  await approve.click()

  await expect(dialog).toHaveCount(0)
  await expect(page.getByTestId('approval-state-line')).toContainText(`by ${releaser}`)
  const decided = await call(page, 'GET', `/approvals/${approval.id}`)
  expect(decided.body.state).toBe('approved')
  expect(decided.body.decidedBy).toMatchObject({ kind: 'web', personName: releaser })

  // The job goes on past the gate and ends.
  await page.getByTestId('approval-detail').getByRole('link', { name: 'ship' }).click()
  await expect(page.locator('h1 + .badge')).toHaveText('Succeeded', { timeout: 60_000 })
  await expect(page.getByRole('log', { name: 'Job log' }).getByText('shipped', { exact: true })).toBeVisible()
  await expect(page.getByTestId('needs-you')).toHaveCount(0)
})

test('a decision that loses the race shows who decided first', async ({ page, browser }, testInfo) => {
  // This tab hears nothing from the engine, so only the 409 can tell it.
  await page.routeWebSocket(/\/api\/v1\/events/, () => {})
  await signIn(page, releaser)
  const approval = await dispatchToGate(page)

  await page.goto(`/approvals/${approval.id}`)
  await page.getByRole('button', { name: 'Approve…' }).click()
  const dialog = page.getByRole('dialog', { name: 'Review the approval' })
  const approve = dialog.getByRole('button', { name: 'Approve', exact: true })
  await expect(approve).toBeEnabled()

  const other = await pageOf(browser, testInfo.project.use.baseURL, otherReleaser)
  const denied = await call(other, 'POST', `/approvals/${approval.id}/deny`, { reason: 'Not this one.' })
  expect(denied.status).toBe(200)
  await other.close()

  const answer = page.waitForResponse((response) => response.url().endsWith(`/approvals/${approval.id}/approve`))
  await approve.click()
  expect((await answer).status()).toBe(409)
  await expect(dialog.getByTestId('already-decided')).toHaveText(
    `Already denied by ${otherReleaser}. The first decision counts; nothing to do here.`,
  )
})
