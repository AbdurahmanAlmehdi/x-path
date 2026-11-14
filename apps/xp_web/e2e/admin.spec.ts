import { expect, type Page, type Response, test } from '@playwright/test'

import { signInCode } from './engine'

// The engine's first admin: every new database has `Owner`, and no other
// spec makes an admin, so Owner is the last admin here.
const owner = 'Owner'

// A made-up keystore and password: obviously fake, never a real key. The
// engine checks keystores with `keytool`, which web_e2e.sh replaces with a
// shim that accepts any.
const keystoreBytes = Buffer.from('XPATH-E2E-FAKE-KEYSTORE-NOT-A-REAL-KEY')
const keystorePassword = 'xpath-e2e-fake-store-password'

/**
 * Keeps the body of every response [page] gets, so the spec can say no
 * response carried a secret it sent.
 */
function recordResponses(page: Page): Promise<string>[] {
  const bodies: Promise<string>[] = []
  page.on('response', (response: Response) => {
    bodies.push(response.body().then((body) => body.toString('utf8')).catch(() => ''))
  })
  return bodies
}

test('an admin manages people, credentials and runners, and a demoted person loses the button', async ({
  page,
  context,
  browser,
  baseURL,
}) => {
  test.setTimeout(90_000)
  await context.grantPermissions(['clipboard-read', 'clipboard-write'])
  const bodies = recordResponses(page)
  const developer = `Dana ${Date.now()}`
  let code = ''

  await test.step('the admin signs in', async () => {
    await page.goto(`/sign-in#code=${signInCode(owner)}`)
    await expect(page.getByTestId('person-name')).toHaveText(owner)
  })

  await test.step('the admin adds a developer and copies the code shown once', async () => {
    await page.goto('/people')
    await page.getByRole('button', { name: 'Add person…' }).click()
    const dialog = page.getByRole('dialog', { name: 'Add a person' })
    await dialog.getByLabel('Name').fill(developer)
    await dialog.getByLabel('Role').selectOption('developer')
    await dialog.getByRole('button', { name: 'Add', exact: true }).click()

    const shown = page.getByRole('dialog', { name: `Added ${developer}` })
    await expect(shown).toContainText(/[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}/)
    await shown.getByRole('button', { name: 'Copy code' }).click()
    await expect(shown.getByRole('button', { name: 'Copied' })).toBeVisible()
    code = await page.evaluate(() => navigator.clipboard.readText())
    expect(code).toMatch(/^[0-9A-Z]{4}(-[0-9A-Z]{4}){3}$/)
    expect(page.url()).not.toContain(code)
    const stored = await page.evaluate(() => JSON.stringify({ ...localStorage, ...sessionStorage }))
    expect(stored).not.toContain(code)

    await shown.getByRole('button', { name: 'Done' }).click()
    await expect(page.locator('body')).not.toContainText(code)
    await expect(page.locator(`[data-person="${developer}"]`)).toContainText('developer')
  })

  const other = await browser.newContext({ baseURL })
  const developerPage = await other.newPage()

  await test.step('a second browser signs in with the copied code', async () => {
    await developerPage.goto('/sign-in')
    await developerPage.getByLabel('Sign-in code').fill(code)
    await developerPage.getByRole('button', { name: 'Sign in' }).click()
    await expect(developerPage.getByTestId('person-name')).toHaveText(developer)
    await expect(developerPage.locator('.role')).toHaveText('developer')
  })

  await test.step('after a demotion the next action gets 403, and the page reads /me again and hides the button', async () => {
    await developerPage.goto('/projects')
    await developerPage.getByRole('link', { name: 'Add project…' }).click()
    await developerPage.getByLabel('Repository').fill('acme/never-added')

    await page.goto('/people')
    const demoted = page.waitForResponse(
      (response) => response.request().method() === 'PATCH' && response.url().includes('/api/v1/people/'),
    )
    await page.getByLabel(`Role of ${developer}`).selectOption('viewer')
    expect((await demoted).status()).toBe(200)

    const refused = developerPage.waitForResponse(
      (response) => response.request().method() === 'POST' && response.url().endsWith('/api/v1/projects'),
    )
    const reread = developerPage.waitForResponse(
      (response) => response.request().method() === 'GET' && response.url().endsWith('/api/v1/me'),
    )
    await developerPage.getByRole('button', { name: 'Add and scan' }).click()
    expect((await refused).status()).toBe(403)
    expect((await reread).status()).toBe(200)

    await expect(developerPage.locator('.role')).toHaveText('viewer')
    await expect(developerPage.getByTestId('cannot-add')).toBeVisible()
    await expect(developerPage.getByRole('button', { name: 'Add and scan' })).toHaveCount(0)
    await developerPage.goto('/projects')
    await expect(developerPage.getByRole('heading', { name: 'Projects', exact: true })).toBeVisible()
    await expect(developerPage.getByRole('link', { name: 'Add project…' })).toHaveCount(0)
  })
  await other.close()

  await test.step('uploading a keystore stores a credential, and no response carries its bytes', async () => {
    await page.goto('/credentials')
    await page.getByRole('button', { name: 'Add credential…' }).click()
    const form = page.getByTestId('credential-form')
    await form.getByLabel('Name', { exact: true }).fill('E2E upload keystore')
    await form.getByLabel('Kind').selectOption('keystore')
    await form.getByLabel('Keystore', { exact: true }).setInputFiles({
      name: 'upload.jks',
      mimeType: 'application/octet-stream',
      buffer: keystoreBytes,
    })
    await expect(form.getByTestId('file-chosen')).toHaveText(`upload.jks · ${keystoreBytes.length} B`)
    const password = form.getByLabel('Store password', { exact: true })
    await expect(password).toHaveAttribute('type', 'password')
    await expect(password).toHaveAttribute('autocomplete', 'new-password')
    await password.fill(keystorePassword)
    await form.getByLabel('Key alias').fill('upload')

    const sent = page.waitForRequest(
      (request) => request.method() === 'POST' && request.url().endsWith('/api/v1/credentials'),
    )
    const stored = page.waitForResponse(
      (response) => response.request().method() === 'POST' && response.url().endsWith('/api/v1/credentials'),
    )
    await form.getByRole('button', { name: 'Check and save' }).click()
    expect(JSON.parse((await sent).postData() ?? '{}')).toMatchObject({
      kind: 'keystore',
      keystore: keystoreBytes.toString('base64'),
      keyAlias: 'upload',
    })
    expect((await stored).status()).toBe(201)

    const row = page.locator('[data-credential="E2E upload keystore"]')
    await expect(row).toContainText('Android keystore')
    await expect(row).toContainText('Verified')
    await expect(page.getByTestId('credential-form')).toHaveCount(0)
    const html = await page.content()
    expect(html).not.toContain(keystoreBytes.toString('utf8'))
    expect(html).not.toContain(keystoreBytes.toString('base64'))
    expect(html).not.toContain(keystorePassword)
  })

  await test.step('a pairing token is shown once, never in the address or storage', async () => {
    await page.goto('/runners')
    await page.getByRole('button', { name: 'Pair runner…' }).click()
    const dialog = page.getByRole('dialog', { name: 'Pair a runner' })
    await dialog.getByLabel('Name').fill(`e2e-runner-${Date.now()}`)
    await dialog.getByRole('button', { name: 'Create pairing token' }).click()
    const command = dialog.locator('code').nth(1)
    await expect(command).toContainText('xp runner pair --engine')
    const token = (await dialog.locator('code').first().textContent()) ?? ''
    expect(token).toMatch(/^xpp_/)
    expect(page.url()).not.toContain(token)
    const kept = await page.evaluate(() => JSON.stringify({ ...localStorage, ...sessionStorage }))
    expect(kept).not.toContain(token)
    await dialog.getByRole('button', { name: 'Done' }).click()
    await expect(page.locator('body')).not.toContainText(token)
  })

  await test.step('demoting the last admin gets a clear 409 message', async () => {
    await page.goto('/people')
    const refused = page.waitForResponse(
      (response) => response.request().method() === 'PATCH' && response.url().includes('/api/v1/people/'),
    )
    await page.getByLabel(`Role of ${owner}`).selectOption('developer')
    expect((await refused).status()).toBe(409)
    await expect(page.getByTestId('people-error')).toHaveText(
      'Cannot demote Owner: they are the last admin. Make someone else an admin first.',
    )
    await expect(page.getByLabel(`Role of ${owner}`)).toHaveValue('admin')
    await expect(page.locator('.role')).toHaveText('admin')
  })

  await test.step('no response of the session carried the keystore or its password', async () => {
    const texts = await Promise.all(bodies)
    expect(texts.length).toBeGreaterThan(0)
    for (const text of texts) {
      expect(text).not.toContain(keystoreBytes.toString('utf8'))
      expect(text).not.toContain(keystoreBytes.toString('base64'))
      expect(text).not.toContain(keystorePassword)
    }
  })
})
