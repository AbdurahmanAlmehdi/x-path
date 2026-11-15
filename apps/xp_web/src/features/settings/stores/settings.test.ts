import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'

import { useSettingsStore } from './settings'

describe('useSettingsStore', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('reads the public URL, the runner URL and whether the engine has its GitHub token', async () => {
    stubEngine({
      'GET /settings/public-url': { status: 200, body: { url: 'https://xpath.example.com' } },
      'GET /settings/runner-url': { status: 200, body: { url: 'http://mac-mini.local:7480' } },
      'GET /github-token': { status: 200, body: { stored: true, status: 'verified', login: 'octo' } },
    })
    const store = useSettingsStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.publicUrl).toBe('https://xpath.example.com')
    expect(store.runnerUrl).toBe('http://mac-mini.local:7480')
    expect(store.github).toEqual({ stored: true, status: 'verified', login: 'octo' })
    expect(store.errors).toEqual({})
  })

  it('reads unset URLs as none, and says what could not be read', async () => {
    stubEngine({
      'GET /settings/public-url': { status: 200, body: {} },
      'GET /settings/runner-url': { status: 200, body: {} },
      'GET /github-token': { status: 503, body: errorBody('secrets_locked', 'The secrets are locked.') },
    })
    const store = useSettingsStore()

    await store.load()

    expect(store.publicUrl).toBeNull()
    expect(store.runnerUrl).toBeNull()
    expect(store.errors).toEqual({ github: 'The secrets are locked.' })
  })

  it('says every part when the engine does not answer', async () => {
    stubUnreachableEngine()
    const store = useSettingsStore()

    await store.load()

    expect(Object.keys(store.errors).sort()).toEqual(['github', 'publicUrl', 'runnerUrl'])
  })

  it('sets and clears the public URL', async () => {
    const seen = stubEngine({
      'PUT /settings/public-url': () => {
        const body = seen.at(-1)?.body as { url: string | null }
        return { status: 200, body: body.url ? { url: body.url } : {} }
      },
    })
    const store = useSettingsStore()

    expect(await store.setPublicUrl(' https://xpath.example.com ')).toBe(true)
    expect(store.publicUrl).toBe('https://xpath.example.com')
    expect(await store.setPublicUrl(null)).toBe(true)
    expect(store.publicUrl).toBeNull()
    expect(seen.map((request) => request.body)).toEqual([{ url: 'https://xpath.example.com' }, { url: null }])
  })

  it('sets the runner URL with the warning the engine gives, clears it, and keeps a refusal apart', async () => {
    let refuse = false
    const seen = stubEngine({
      'PUT /settings/runner-url': () => {
        if (refuse) return { status: 400, body: errorBody('invalid_request', 'Not a URL.') }
        const body = seen.at(-1)?.body as { url: string | null }
        return {
          status: 200,
          body: body.url ? { url: body.url, warning: 'Plain http leaves this machine.' } : {},
        }
      },
      'PUT /settings/public-url': { status: 400, body: errorBody('invalid_request', 'Not https.') },
    })
    const store = useSettingsStore()

    expect(await store.setRunnerUrl('http://192.168.1.2:7480')).toBe(true)
    expect(store.runnerUrl).toBe('http://192.168.1.2:7480')
    expect(store.runnerUrlWarning).toBe('Plain http leaves this machine.')
    expect(await store.setRunnerUrl(null)).toBe(true)
    expect(store.runnerUrl).toBeNull()
    expect(store.runnerUrlWarning).toBeNull()

    await store.setPublicUrl('http://nope')
    refuse = true
    expect(await store.setRunnerUrl('nope')).toBe(false)
    expect(store.errors).toEqual({ publicUrl: 'Not https.', runnerUrl: 'Not a URL.' })
    expect(store.saving).toBeNull()
  })

  it('hands the GitHub token to the engine and keeps only what GitHub said', async () => {
    const seen = stubEngine({
      'PUT /github-token': { status: 200, body: { stored: true, status: 'verified', login: 'octo' } },
    })
    const store = useSettingsStore()

    expect(await store.saveGitHubToken(' ghp_fake ')).toBe(true)

    expect(seen[0]?.body).toEqual({ token: 'ghp_fake' })
    expect(store.github?.login).toBe('octo')
    expect(JSON.stringify(store.$state)).not.toContain('ghp_fake')
  })

  it('says why GitHub refused the token, imports the one of gh and removes it', async () => {
    stubEngine({
      'PUT /github-token': { status: 422, body: errorBody('credential_rejected', 'GitHub refused it.') },
      'POST /github-token/import': { status: 200, body: { stored: true, status: 'verified', login: 'gh-user' } },
      'DELETE /github-token': { status: 204 },
    })
    const store = useSettingsStore()

    expect(await store.saveGitHubToken('ghp_bad')).toBe(false)
    expect(store.errors.github).toBe('GitHub refused it.')

    expect(await store.importGitHubToken()).toBe(true)
    expect(store.errors.github).toBeUndefined()
    expect(store.github?.login).toBe('gh-user')

    expect(await store.removeGitHubToken()).toBe(true)
    expect(store.github).toEqual({ stored: false })
  })

  it('says why the token could not be removed', async () => {
    stubEngine({ 'DELETE /github-token': { status: 403, body: errorBody('forbidden', 'Admins only.') } })
    const store = useSettingsStore()

    expect(await store.removeGitHubToken()).toBe(false)
    expect(store.errors.github).toBe('Admins only.')
  })

  it('reads the runner URL alone, for the pairing dialog', async () => {
    stubEngine({ 'GET /settings/runner-url': { status: 200, body: { url: 'http://box:7480' } } })
    const store = useSettingsStore()

    await store.loadRunnerUrl()

    expect(store.runnerUrl).toBe('http://box:7480')
  })
})
