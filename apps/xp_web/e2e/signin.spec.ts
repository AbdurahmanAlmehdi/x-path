import { expect, test } from '@playwright/test'

import { createPerson, signInCode } from './engine'

let name: string

test.beforeAll(({}, testInfo) => {
  name = `Sam ${testInfo.project.name}`
  createPerson(name, 'developer')
})

test('a signed-out deep link signs in and returns there', async ({ page, context, baseURL }) => {
  await page.goto('/runs/abc')

  await expect(page).toHaveURL(/\/sign-in\?next=/)
  expect(new URL(page.url()).searchParams.get('next')).toBe('/runs/abc')

  await page.getByLabel('Sign-in code').fill(signInCode(name))
  await page.getByRole('button', { name: 'Sign in' }).click()

  await expect(page).toHaveURL(`${baseURL}/runs/abc`)
  await expect(page.getByTestId('person-name')).toHaveText(name)
  const [cookie] = await context.cookies()
  expect(cookie).toMatchObject({
    name: `xp_session_${new URL(baseURL!).port}`,
    path: '/',
    httpOnly: true,
    secure: false,
    sameSite: 'Strict',
  })
})

test('a code in the fragment signs in and leaves the address', async ({ page, baseURL }) => {
  const code = signInCode(name)

  await page.goto(`/sign-in?next=%2Fprojects#code=${code}`)

  await expect(page).toHaveURL(`${baseURL}/projects`)
  await expect(page.getByTestId('person-name')).toHaveText(name)
  await page.goBack()
  expect(page.url()).not.toContain(code)
})

test('a next to another site is ignored', async ({ page, baseURL }) => {
  await page.goto(`/sign-in?next=%2F%2Fevil.example#code=${signInCode(name)}`)

  await expect(page.getByRole('heading', { name: `Welcome, ${name}` })).toBeVisible()
  expect(page.url()).toBe(`${baseURL}/`)
})

test('a wrong code is refused', async ({ page }) => {
  await page.goto('/sign-in')

  await page.getByLabel('Sign-in code').fill('AAAA-AAAA-AAAA-AAAA')
  await page.getByRole('button', { name: 'Sign in' }).click()

  await expect(page.getByRole('alert')).toHaveText(
    'That code is wrong, used or expired. Ask for a new one.',
  )
  await expect(page).toHaveURL(/\/sign-in$/)
})

test('signing out ends the session on the engine', async ({ page }) => {
  await page.goto(`/sign-in#code=${signInCode(name)}`)
  await expect(page.getByTestId('person-name')).toHaveText(name)

  await page.getByRole('button', { name: 'Sign out' }).click()

  await expect(page).toHaveURL(/\/sign-in$/)
  const me = await page.request.get('/api/v1/me')
  expect(me.status()).toBe(401)
  await page.goto('/runs')
  await expect(page).toHaveURL(/\/sign-in\?next=/)
})

test('the dashboard is served with its security headers, and keeps to them', async ({ page }) => {
  const violations: string[] = []
  page.on('console', (message) => {
    if (message.text().includes('Content Security Policy')) violations.push(message.text())
  })

  const response = await page.goto('/sign-in')
  await expect(page.getByLabel('Sign-in code')).toBeVisible()

  const headers = response?.headers() ?? {}
  expect(headers['content-security-policy']).toContain("script-src 'self'")
  expect(headers['content-security-policy']).toContain("frame-ancestors 'none'")
  expect(headers['x-content-type-options']).toBe('nosniff')
  expect(headers['referrer-policy']).toBe('no-referrer')
  expect(violations).toEqual([])
})
