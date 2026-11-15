import { DOMWrapper, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import type { Router } from 'vue-router'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { flavorCredentialOf, namedCredentialOf, projectOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

describe('CredentialsView', () => {
  let app: VueWrapper | undefined
  let router: Router
  /** The bytes of a made-up keystore: never a real key. */
  const keystoreText = 'FAKE-KEYSTORE-FOR-TESTS'
  const keystoreBase64 = btoa(keystoreText)

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, admin = true) {
    return stubEngine({
      'GET /me': { status: 200, body: admin ? meOf() : meOf('developer', ['develop']) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /projects': {
        status: 200,
        body: { projects: [projectOf(), projectOf({ id: 'prj_2', fullName: 'acme/other' })] },
      },
      'GET /credentials': {
        status: 200,
        body: {
          credentials: [
            namedCredentialOf(),
            namedCredentialOf({
              id: 'crd_2',
              name: 'Team key',
              kind: 'asc_key',
              status: 'rejected',
              message: 'The key was revoked.',
              fix: 'Make a new one.',
              account: undefined,
              usedBy: [],
            }),
          ],
        },
      },
      'GET /projects/prj_1/credentials': { status: 200, body: { credentials: [flavorCredentialOf()] } },
      'GET /projects/prj_2/credentials': { status: 200, body: { credentials: [] } },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  function row(name: string) {
    return app!.find(`[data-credential="${name}"]`)
  }

  function form() {
    return app!.find('[data-testid="credential-form"]')
  }

  async function pick(input: DOMWrapper<Element>, file: File) {
    Object.defineProperty(input.element, 'files', { value: [file], configurable: true })
    await input.trigger('change')
  }

  it('lists the credentials, never a secret, and the credentials of each flavor', async () => {
    engine()
    ;({ app } = await openApp('/credentials'))

    expect(row('Upload keystore').text()).toContain('Android keystore')
    expect(row('Upload keystore').text()).toContain('Verified')
    expect(row('Upload keystore').text()).toContain('1 flavor')
    expect(row('Team key').text()).toContain('Rejected')
    expect(row('Team key').text()).toContain('The key was revoked. Make a new one.')
    expect(row('Team key').text()).toContain('Not used')
    const flavors = app.find('[data-testid="flavors"]')
    expect(flavors.find('[data-flavor="dev"]').text()).toContain('Android keystore: Upload keystore')
    expect(flavors.find('[data-flavor="prod"]').text()).toContain('None assigned')
  })

  it('shows a developer no admin action', async () => {
    engine({}, false)
    ;({ app } = await openApp('/credentials'))

    expect(app.findAll('main button')).toHaveLength(0)
  })

  it('uploads a keystore straight from the file picker, and never shows its bytes or passwords', async () => {
    const seen = engine({ 'POST /credentials': { status: 201, body: namedCredentialOf({ id: 'crd_3', name: 'Play key' }) } })
    ;({ app } = await openApp('/credentials'))

    await button('Add credential…').trigger('click')
    await form().find('input[type="text"]').setValue('Play key')
    await form().find('select').setValue('keystore')
    expect(button('Check and save').attributes('disabled')).toBeDefined()

    await pick(form().find('input[type="file"]'), new File([keystoreText], 'upload.jks'))
    expect(form().find('[data-testid="file-chosen"]').text()).toBe('upload.jks · 23 B')
    const password = form().find('input[data-field="storePassword"]')
    expect(password.attributes('type')).toBe('password')
    expect(password.attributes('autocomplete')).toBe('new-password')
    expect(form().find('input[data-field="keyPassword"]').attributes('type')).toBe('password')
    await password.setValue('fake-store-password')
    await form().find('input[data-field="keyAlias"]').setValue('upload')
    expect(app.html()).not.toContain(keystoreText)

    await form().trigger('submit')
    await flushPromises()
    await flushPromises()

    expect(seen.find((request) => request.method === 'POST')?.body).toEqual({
      name: 'Play key',
      kind: 'keystore',
      keystore: keystoreBase64,
      storePassword: 'fake-store-password',
      keyAlias: 'upload',
    })
    expect(form().exists()).toBe(false)
    expect(app.find('[data-testid="credentials-notice"]').text()).toBe('Credential saved')
    expect(app.html()).not.toContain(keystoreText)
    expect(app.html()).not.toContain(keystoreBase64)
    expect(app.html()).not.toContain('fake-store-password')
  })

  it('reads a .p8 key as text, with its key type, and keeps the form with a refusal', async () => {
    const seen = engine({
      'POST /credentials': {
        status: 422,
        body: errorBody('credential_rejected', 'App Store Connect refused the key.', 'Check the issuer ID.'),
      },
    })
    ;({ app } = await openApp('/credentials'))

    await button('Add credential…').trigger('click')
    await form().find('input[type="text"]').setValue('Team key')
    await form().findAll('select')[1]!.setValue('individual')
    await form().find('input[data-field="keyId"]').setValue('ABC123')
    await form().find('input[data-field="issuerId"]').setValue('issuer')
    const file = form().find('input[type="file"]')
    expect(file.attributes('accept')).toBe('.p8')
    await pick(file, new File(['FAKE P8 KEY'], 'AuthKey.p8'))
    await pick(file, new File([], 'none'))
    Object.defineProperty(file.element, 'files', { value: [], configurable: true })
    await file.trigger('change')
    expect(button('Check and save').attributes('disabled')).toBeDefined()
    await pick(file, new File(['FAKE P8 KEY'], 'AuthKey.p8'))
    await form().trigger('submit')
    await flushPromises()
    await flushPromises()

    expect(seen.find((request) => request.method === 'POST')?.body).toEqual({
      name: 'Team key',
      kind: 'asc_key',
      keyId: 'ABC123',
      issuerId: 'issuer',
      privateKey: 'FAKE P8 KEY',
      keyKind: 'individual',
    })
    expect(form().find('[role="alert"]').text()).toBe(
      'Not saved: App Store Connect refused the key. Check the issuer ID.',
    )
    expect(app.html()).not.toContain('FAKE P8 KEY')

    await button('Cancel').trigger('click')
    expect(form().exists()).toBe(false)
  })

  it('replaces a secret, renames and checks a credential', async () => {
    const seen = engine({
      'PUT /credentials/crd_2': { status: 200, body: namedCredentialOf({ id: 'crd_2' }) },
      'PATCH /credentials/crd_2': { status: 200, body: namedCredentialOf({ id: 'crd_2', name: 'Team key 2' }) },
      'POST /credentials/crd_2/verify': { status: 200, body: namedCredentialOf({ id: 'crd_2', name: 'Team key' }) },
    })
    ;({ app } = await openApp('/credentials'))

    await row('Team key').findAll('button').find((each) => each.text() === 'Replace secret…')!.trigger('click')
    expect(form().text()).toContain('Replace the secret of Team key')
    await form().find('input[data-field="keyId"]').setValue('NEW')
    await form().find('input[data-field="issuerId"]').setValue('issuer')
    await pick(form().find('input[type="file"]'), new File(['FAKE P8'], 'AuthKey.p8'))
    await form().trigger('submit')
    await flushPromises()
    await flushPromises()
    expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({
      kind: 'asc_key',
      keyId: 'NEW',
      issuerId: 'issuer',
      privateKey: 'FAKE P8',
      keyKind: 'team',
    })

    await row('Team key').findAll('button').find((each) => each.text() === 'Rename…')!.trigger('click')
    await app.find('[role="dialog"] input').setValue('Team key 2')
    await button('Rename').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(app.find('[data-testid="credentials-notice"]').text()).toBe('Renamed to Team key 2')

    await row('Team key').findAll('button').find((each) => each.text() === 'Check now')!.trigger('click')
    await flushPromises()
    expect(app.find('[data-testid="credentials-notice"]').text()).toBe('Checked Team key: Verified')
  })

  it('keeps the rename open with its refusal, and closes it on Cancel', async () => {
    engine({ 'PATCH /credentials/crd_2': { status: 409, body: errorBody('conflict', 'The name is taken.') } })
    ;({ app } = await openApp('/credentials'))

    await row('Team key').findAll('button').find((each) => each.text() === 'Rename…')!.trigger('click')
    await app.find('[role="dialog"] form').trigger('submit')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('The name is taken.')
    await button('Cancel').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('deletes a credential flavors use only after saying which, unassigning them', async () => {
    const seen = engine({
      'DELETE /credentials/crd_1': { status: 204 },
      'DELETE /credentials/crd_2': { status: 503, body: errorBody('secrets_locked', 'The secrets are locked.') },
    })
    ;({ app } = await openApp('/credentials'))

    await row('Team key').findAll('button').find((each) => each.text() === 'Delete…')!.trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain('No flavor uses it.')
    await button('Delete').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('The secrets are locked.')
    await button('Keep it').trigger('click')

    await row('Upload keystore').findAll('button').find((each) => each.text() === 'Delete…')!.trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain(
      '1 flavor uses it. They will have no Android keystore until you assign another: acme/app · dev',
    )
    await button('Unassign and delete').trigger('click')
    await flushPromises()
    expect(seen.some((request) => request.method === 'DELETE' && request.search === '?force=true')).toBe(true)
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('assigns a credential to a flavor and takes it away', async () => {
    let assigned = false
    const seen = engine({
      'GET /projects/prj_1/credentials': () => ({
        status: 200,
        body: {
          credentials: assigned
            ? [flavorCredentialOf(), flavorCredentialOf({ flavor: 'prod', kind: 'asc_key', name: 'Team key', status: 'rejected', message: 'Revoked.' })]
            : [flavorCredentialOf()],
        },
      }),
      'PUT /projects/prj_1/flavors/prod/credentials/asc_key': () => {
        assigned = true
        return { status: 200, body: { assigned: [], kept: [flavorCredentialOf()] } }
      },
      'DELETE /projects/prj_1/flavors/prod/credentials/asc_key': { status: 403, body: errorBody('forbidden', 'No.') },
    })
    ;({ app } = await openApp('/credentials'))

    await app.find('[data-flavor="prod"] button').trigger('click')
    const dialog = () => app!.find('[role="dialog"]')
    expect(dialog().attributes('aria-label')).toBe('Credentials of prod')
    expect(dialog().text()).toContain('None assigned')
    expect((dialog().findAll('select')[1]!.element as HTMLSelectElement).value).toBe('crd_2')
    await dialog().findAll('input[type="radio"]')[1]!.setValue(true)
    expect(dialog().text()).toContain('Flavors that have their own App Store Connect API key keep it.')
    await dialog().find('input[type="checkbox"]').setValue(true)
    expect(dialog().text()).toContain('Every flavor of the app uses this App Store Connect API key')
    await dialog().find('input[type="checkbox"]').setValue(false)
    await button('Assign').trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({
      credentialId: 'crd_2',
      allFlavors: true,
      replace: false,
    })
    expect(dialog().text()).toContain('dev kept their own credential.')
    expect(dialog().text()).toContain('App Store Connect API key: Team key')
    expect(dialog().text()).toContain('Revoked.')
    expect(app.find('[data-flavor="prod"]').text()).toContain('Rejected')

    await dialog().findAll('button').find((each) => each.text() === 'Change…')!.trigger('click')
    expect((dialog().findAll('select')[0]!.element as HTMLSelectElement).value).toBe('asc_key')
    await dialog().findAll('select')[0]!.setValue('slack')
    expect(dialog().text()).toContain('No Slack webhook yet.')
    await dialog().findAll('button').find((each) => each.text() === 'Remove from this flavor')!.trigger('click')
    await flushPromises()
    expect(dialog().find('[role="alert"]').text()).toBe('No.')

    await button('Done').trigger('click')
    expect(dialog().exists()).toBe(false)
  })

  describe('creating a distribution certificate', () => {
    const path = 'POST /projects/prj_1/flavors/prod/distribution-certificate'
    const dialog = () => app!.find('[role="dialog"]')
    const actionsOf = (flavor: string) =>
      app!
        .find(`[data-flavor="${flavor}"]`)
        .findAll('button')
        .map((each) => each.text())

    async function openCreate() {
      await app!
        .find('[data-flavor="prod"]')
        .findAll('button')
        .find((each) => each.text() === 'Create certificate…')!
        .trigger('click')
    }

    it("offers it to an iOS flavor without an identity, and lists the team's certificates at Apple's limit", async () => {
      let attempts = 0
      const seen = engine({
        'GET /projects/prj_1/credentials': {
          status: 200,
          body: { credentials: [flavorCredentialOf({ kind: 'apple_distribution', name: 'Dev identity' })] },
        },
        [path]: () =>
          ++attempts === 1
            ? {
                status: 409,
                body: {
                  error: {
                    code: 'conflict',
                    message: "The team has 3 distribution certificates, Apple's limit is 3.",
                    hint: 'Revoke one with --private-key.',
                    details: {
                      reason: 'certificate_limit',
                      limit: 3,
                      certificates: [
                        { id: 'a', serialNumber: '0A', name: 'Apple Distribution: Acme', expirationDate: '2027-01-02T00:00:00Z' },
                        { id: 'b', serialNumber: '0B' },
                        { id: 'c', serialNumber: '0C' },
                      ],
                    },
                  },
                },
              }
            : { status: 201, body: namedCredentialOf({ id: 'crd_9', name: 'Another', kind: 'apple_distribution' }) },
      })
      ;({ app } = await openApp('/credentials'))

      expect(actionsOf('dev')).toEqual(['Manage…'])
      expect(actionsOf('prod')).toEqual(['Manage…', 'Create certificate…'])
      await openCreate()
      expect(dialog().attributes('aria-label')).toBe('Create certificate for prod')
      expect(dialog().text()).toContain("with this flavor's App Store Connect key and assigns it. Apple allows a team three.")
      expect((dialog().find('input').element as HTMLInputElement).value).toBe('Apple Distribution · acme/app prod')

      await button('Create certificate').trigger('click')
      await flushPromises()
      const limit = dialog().find('[data-testid="certificate-limit"]')
      expect(limit.text()).toContain("The team has 3 distribution certificates, Apple's limit is 3:")
      expect(limit.findAll('li').map((each) => each.text())).toEqual([
        'Apple Distribution: Acme · serial 0A · expires 2027-01-02',
        'A certificate · serial 0B',
        'A certificate · serial 0C',
      ])
      expect(limit.text()).toContain('Revoke one in App Store Connect (Certificates, Identifiers & Profiles)')
      expect(limit.text()).not.toContain('--private-key')

      await dialog().find('input').setValue('Another')
      await dialog().find('form').trigger('submit')
      await flushPromises()

      expect(seen.filter((request) => request.method === 'POST').map((request) => request.body)).toEqual([
        { name: 'Apple Distribution · acme/app prod' },
        { name: 'Another' },
      ])
      expect(dialog().exists()).toBe(false)
    })

    it('says why the engine refused, starts afresh, and is not offered for an app without iOS', async () => {
      const android = projectOf({ id: 'prj_2', fullName: 'acme/other' })
      android.profile.apps[0]!.hasIos = false
      const seen = engine({
        'GET /projects': { status: 200, body: { projects: [projectOf(), android] } },
        [path]: { status: 400, body: errorBody('invalid_request', 'The flavor prod has no App Store Connect API key.') },
      })
      ;({ app, router } = await openApp('/credentials'))

      await openCreate()
      await dialog().find('input').setValue('  ')
      expect(button('Create certificate').attributes('disabled')).toBeDefined()
      await dialog().find('form').trigger('submit')
      expect(seen.some((request) => request.method === 'POST')).toBe(false)

      await dialog().find('input').setValue('Linux signing')
      await button('Create certificate').trigger('click')
      await flushPromises()
      expect(dialog().find('[role="alert"]').text()).toBe('The flavor prod has no App Store Connect API key.')
      expect(dialog().find('[data-testid="certificate-limit"]').exists()).toBe(false)

      await button('Cancel').trigger('click')
      expect(dialog().exists()).toBe(false)
      await openCreate()
      expect(dialog().find('[role="alert"]').exists()).toBe(false)
      await button('Cancel').trigger('click')

      await router.replace({ query: { project: 'prj_2' } })
      await flushPromises()
      expect(actionsOf('prod')).toEqual(['Manage…'])
    })
  })

  it('shows the flavors of the project picked, and follows the credential events', async () => {
    const seen = engine()
    ;({ app, router } = await openApp('/credentials?project=prj_2'))

    const picker = app.find('select[aria-label="Project"]')
    expect((picker.element as HTMLSelectElement).value).toBe('prj_2')
    await picker.setValue('prj_1')
    await flushPromises()
    expect(router.currentRoute.value.query.project).toBe('prj_1')

    const before = seen.length
    openEventFeed().send('credential.verified')
    await flushPromises()
    expect(seen.slice(before).map((request) => request.path)).toEqual(
      expect.arrayContaining(['/credentials', '/projects/prj_1/credentials']),
    )
  })

  it('says when there is nothing yet', async () => {
    engine({
      'GET /projects': { status: 200, body: { projects: [] } },
      'GET /credentials': { status: 200, body: { credentials: [] } },
    })
    ;({ app } = await openApp('/credentials'))

    expect(app.text()).toContain('No credentials yet.')
    expect(app.text()).toContain('Add a project to give its flavors credentials.')
  })
})
