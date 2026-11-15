import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { projectOf } from '@/testing/fixtures'

import { useAddProjectStore } from './addProject'

describe('useAddProjectStore', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('adds a repository from a git URL, then the scan is under review', async () => {
    const seen = stubEngine({ 'POST /projects': { status: 201, body: projectOf() } })
    const store = useAddProjectStore()

    expect(await store.add('remote', ' acme/app ')).toBe(true)

    expect(seen[0]?.body).toEqual({ remote: 'acme/app' })
    expect(store.status).toBe('review')
    expect(store.project?.fullName).toBe('acme/app')
  })

  it('adds a folder, and offers the SSH URL of an HTTPS origin outside GitHub', async () => {
    const seen = stubEngine({
      'POST /projects': () =>
        (seen.at(-1)?.body as { sshUrl?: string }).sshUrl
          ? { status: 201, body: projectOf() }
          : {
              status: 422,
              body: {
                error: { code: 'ssh_url_required', message: 'XPath reads this host over SSH.' },
                sshUrl: 'git@bitbucket.org:ws/app.git',
              },
            },
    })
    const store = useAddProjectStore()

    expect(await store.add('path', '/src/app')).toBe(false)
    expect(store.status).toBe('failed')
    expect(store.sshUrl).toBe('git@bitbucket.org:ws/app.git')
    expect(store.error).toBe('XPath reads this host over SSH.')

    expect(await store.add('path', '/src/app', 'git@bitbucket.org:ws/app.git')).toBe(true)
    expect(seen[1]?.body).toEqual({ path: '/src/app', sshUrl: 'git@bitbucket.org:ws/app.git' })
    expect(store.sshUrl).toBeNull()
  })

  it('says why a project was not added', async () => {
    stubEngine({ 'POST /projects': { status: 409, body: errorBody('conflict', 'acme/app is a project already.') } })
    const store = useAddProjectStore()

    await store.add('remote', 'acme/app')
    expect(store.error).toBe('acme/app is a project already.')
    expect(store.sshUrl).toBeNull()

    stubUnreachableEngine()
    await store.add('remote', 'acme/app')
    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('scans the added project again, and keeps the review when the scan fails', async () => {
    let fail = false
    stubEngine({
      'POST /projects': { status: 201, body: projectOf() },
      'POST /projects/prj_1/scan': () =>
        fail
          ? { status: 502, body: errorBody('upstream_error', 'git could not fetch.') }
          : { status: 200, body: projectOf({ findings: [] }) },
    })
    const store = useAddProjectStore()
    await store.rescan()
    expect(store.status).toBe('idle')

    await store.add('remote', 'acme/app')
    await store.rescan()
    expect(store.status).toBe('review')

    fail = true
    await store.rescan()
    expect(store.status).toBe('review')
    expect(store.error).toBe('git could not fetch.')
  })

  it('removes the added project, or says why not, and starts over', async () => {
    let refuse = true
    stubEngine({
      'POST /projects': { status: 201, body: projectOf() },
      'DELETE /projects/prj_1': () =>
        refuse ? { status: 403, body: errorBody('forbidden', 'A developer cannot remove a project.') } : { status: 204 },
    })
    const store = useAddProjectStore()
    expect(await store.discard()).toBe(false)

    await store.add('remote', 'acme/app')
    expect(await store.discard()).toBe(false)
    expect(store.error).toBe('A developer cannot remove a project.')

    refuse = false
    expect(await store.discard()).toBe(true)
    expect(store.status).toBe('discarded')

    store.reset()
    expect(store.status).toBe('idle')
    expect(store.project).toBeNull()
  })
})
