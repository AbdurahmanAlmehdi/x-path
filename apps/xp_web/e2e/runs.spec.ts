import { expect, type Page, test } from '@playwright/test'

import { createPerson, fixtureRepository, signInCode } from './engine'

// The specs of this file build on each other: one project, its runs.
test.describe.configure({ mode: 'serial' })

let developer: string
let viewer: string
let projectId: string
let holdWorkflowId: string

/** How many lines the counting workflow writes, one every tenth of a second. */
const lineCount = 60

const countWorkflow = `schema: 1
name: Count
stages:
  - name: only
    jobs:
      count:
        name: count
        steps:
          - kind: git.checkout
          - kind: command
            with:
              executable: sh
              arguments:
                - -c
                - 'for i in $(seq 1 ${lineCount}); do echo "line $i"; sleep 0.1; done'
`

// A job that runs until it is cancelled, with no toolchain: a checkout,
// then a command that waits. The run stays unfinished, so Cancel is there.
const holdWorkflow = `schema: 1
name: Hold
stages:
  - name: only
    jobs:
      hold:
        name: hold
        steps:
          - kind: git.checkout
          - kind: command
            with:
              executable: sh
              arguments:
                - -c
                - sleep 300
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

/** Fails the test on any Content Security Policy violation of the page. */
function watchPolicy(page: Page): string[] {
  const violations: string[] = []
  page.on('console', (message) => {
    if (message.text().includes('Content Security Policy')) violations.push(message.text())
  })
  page.on('pageerror', (error) => {
    if (error.message.includes('Content Security Policy')) violations.push(error.message)
  })
  return violations
}

test.beforeAll(async ({ browser }, testInfo) => {
  developer = `Dev ${testInfo.project.name}`
  viewer = `Viewer ${testInfo.project.name}`
  createPerson(developer, 'developer')
  createPerson(viewer, 'viewer')

  const page = await browser.newPage({ baseURL: testInfo.project.use.baseURL })
  await signIn(page, developer)
  const added = await call(page, 'POST', '/projects', {
    path: fixtureRepository(`runs-${testInfo.project.name}`),
  })
  expect(added.status).toBe(201)
  projectId = added.body.id
  const workflow = await call(page, 'POST', `/projects/${projectId}/workflows`, {
    name: 'count',
    yaml: countWorkflow,
  })
  expect(workflow.status).toBe(201)
  const hold = await call(page, 'POST', `/projects/${projectId}/workflows`, { name: 'hold', yaml: holdWorkflow })
  expect(hold.status).toBe(201)
  holdWorkflowId = hold.body.id
  await page.close()
})

test('the projects list leads to the project, its apps and flavors', async ({ page }) => {
  await signIn(page, developer)

  await page.getByRole('link', { name: 'Projects' }).click()
  await page.locator(`a[href="/projects/${projectId}"]`).click()

  await expect(page).toHaveURL(new RegExp(`/projects/${projectId}$`))
  await expect(page.getByRole('heading', { name: 'build_app' })).toBeVisible()
  await expect(page.getByRole('cell', { name: 'dev', exact: true })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Dispatch…' })).toBeVisible()
})

test('a viewer sees the project with no Dispatch button', async ({ page }) => {
  await signIn(page, viewer)

  await page.goto(`/projects/${projectId}`)

  await expect(page.getByRole('heading', { name: 'build_app' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Dispatch…' })).toHaveCount(0)
  await page.goto(`/projects/${projectId}/dispatch`)
  await expect(page.getByText('Your role cannot dispatch.')).toBeVisible()
  await expect(page.getByTestId('dispatch')).toHaveCount(0)
})

test('dispatching from the browser starts a run of the person, which they can cancel', async ({ page }) => {
  const violations = watchPolicy(page)
  await signIn(page, developer)
  // The shell follows the events from sign-in on: wait for the socket of the project page.
  const events = page.waitForEvent('websocket', (socket) => socket.url().includes('/api/v1/events'))
  await page.goto(`/projects/${projectId}`)

  // The event feed connects under the dashboard's CSP.
  const feed = await events
  await feed.waitForEvent('framereceived')
  expect(feed.isClosed()).toBe(false)

  await page.getByRole('link', { name: 'Dispatch…' }).click()
  const workflows = page.getByLabel('Workflow')
  // The built-in workflows are on offer; running a real build is not the point here.
  await expect(workflows.locator('option', { hasText: 'Dev build (built-in)' })).toHaveCount(1)
  await workflows.selectOption(holdWorkflowId)
  await page.getByRole('checkbox', { name: 'Android' }).check()
  await page.getByRole('checkbox', { name: 'iOS' }).uncheck()
  await page.getByRole('checkbox', { name: 'dev' }).check()
  await page.getByRole('checkbox', { name: 'prod' }).uncheck()
  const dispatch = page.getByTestId('dispatch')
  await expect(dispatch).toBeEnabled()
  await dispatch.click()

  await expect(page).toHaveURL(/\/runs\/run_[0-9a-f]+$/)
  await expect(page.getByTestId('run-origin')).toHaveText(developer)
  const runId = page.url().split('/').at(-1)!
  const run = await call(page, 'GET', `/runs/${runId}`)
  expect(run.body.workflowId).toBe(holdWorkflowId)
  expect(run.body.origin).toMatchObject({ kind: 'person', personName: developer })
  expect(run.body.request.platforms).toEqual(['android'])

  // The job waits until it is cancelled.
  await page.getByRole('button', { name: 'Cancel', exact: true }).click()
  await page.getByRole('button', { name: 'Cancel run' }).click()
  await expect(page.locator('h1 + .badge')).toHaveText('Cancelled')
  expect(violations).toEqual([])
})

test('the job page streams its log and survives a reconnect without duplicate lines', async ({
  page,
}) => {
  const violations = watchPolicy(page)
  const logSockets: string[] = []
  // Drops the first log socket after a few lines, as a network would.
  await page.routeWebSocket(/\/api\/v1\/jobs\/[^/]+\/logs/, (socket) => {
    logSockets.push(socket.url())
    const server = socket.connectToServer()
    let frames = 0
    server.onMessage((message) => {
      socket.send(message)
      frames += 1
      if (logSockets.length === 1 && frames === 5) {
        socket.close({ code: 4000, reason: 'dropped by the test' })
        server.close()
      }
    })
  })
  await signIn(page, developer)
  await page.goto(`/projects/${projectId}/dispatch?workflow=count`)
  const dispatch = page.getByTestId('dispatch')
  await expect(dispatch).toHaveText('Dispatch 1 job')
  await dispatch.click()
  await expect(page).toHaveURL(/\/runs\/run_[0-9a-f]+$/)
  await page.getByRole('link', { name: /count/ }).click()

  // Lines show as they come, while the job still runs.
  const log = page.getByRole('log', { name: 'Job log' })
  await expect(log.getByText('line 15', { exact: true })).toBeVisible({ timeout: 30_000 })
  await expect(page.getByTestId('log-count')).toContainText('live')
  await expect(log.getByText(`line ${lineCount}`, { exact: true })).toBeVisible({ timeout: 30_000 })
  await expect(page.locator('h1 + .badge')).toHaveText('Succeeded')

  expect(logSockets.length).toBeGreaterThanOrEqual(2)
  expect(new URL(logSockets[1]!).searchParams.get('after')).not.toBe('0')
  const seqs = await log.locator('.line').evaluateAll((lines) =>
    lines.map((line) => Number((line as HTMLElement).dataset.seq)),
  )
  expect(new Set(seqs).size).toBe(seqs.length)
  expect(seqs).toEqual([...seqs].sort((a, b) => a - b))
  const counted = (await log.locator('.text').allTextContents()).filter((text) => /^line \d+$/.test(text))
  expect(counted).toEqual(Array.from({ length: lineCount }, (_, i) => `line ${i + 1}`))
  expect(violations).toEqual([])
})

test('the log socket connects under the CSP, and the runs list follows the engine', async ({
  page,
}) => {
  const violations = watchPolicy(page)
  await signIn(page, developer)
  await page.goto(`/projects/${projectId}/runs?state=succeeded`)
  await expect(page.getByRole('combobox', { name: 'State' })).toHaveValue('succeeded')
  await expect(page.locator('.run')).toHaveCount(1)

  const logs = page.waitForEvent('websocket', (socket) => socket.url().includes('/logs'))
  await page.locator('.run').first().click()
  await page.getByRole('link', { name: /count/ }).click()
  const socket = await logs
  await socket.waitForEvent('framereceived')
  await expect(page.getByRole('log', { name: 'Job log' }).getByText('line 1', { exact: true })).toBeVisible()

  await page.goto('/runs')
  await expect(page.locator('.run').filter({ hasText: 'Count' }).first()).toBeVisible()
  expect(violations).toEqual([])
})
