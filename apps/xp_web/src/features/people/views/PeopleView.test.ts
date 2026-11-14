import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import type { Router } from 'vue-router'

import type { Person } from '@/api/client'
import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { personOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

describe('PeopleView', () => {
  let app: VueWrapper | undefined
  let router: Router
  const dana = personOf({ id: 'per_2', name: 'Dana', role: 'developer' })
  const code = { code: 'AAAA-BBBB-CCCC-DDDD', personId: 'per_2', expiresAt: '2026-11-14T09:10:00Z' }

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
    localStorage.clear()
    sessionStorage.clear()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, people: Person[] = [personOf(), dana]) {
    return stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /people': () => ({ status: 200, body: { people } }),
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  function row(name: string) {
    return app!.find(`[data-person="${name}"]`)
  }

  it('lists the people with their roles, the signed-in one marked, and the removed apart', async () => {
    engine({}, [personOf(), dana, personOf({ id: 'per_3', name: 'Gone', removedAt: '2026-11-14T10:00:00Z' })])
    ;({ app } = await openApp('/people'))

    expect(row('Sam').text()).toContain('· you')
    expect((row('Dana').find('select').element as HTMLSelectElement).value).toBe('developer')
    expect(app.text()).toContain('Removed')
    expect(app.text()).toContain('Gone')
  })

  it('adds a person and shows their sign-in code once, out of the address and storage', async () => {
    const people = [personOf()]
    const seen = engine(
      {
        'POST /people': () => {
          people.push(dana)
          return { status: 201, body: dana }
        },
        'POST /people/per_2/sign-in-codes': { status: 201, body: code },
      },
      people,
    )
    ;({ app, router } = await openApp('/people'))

    await button('Add person…').trigger('click')
    const dialog = () => app!.find('[role="dialog"]')
    await dialog().find('input').setValue('Dana')
    await dialog().find('select').setValue('developer')
    await button('Add').trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.path === '/people' && request.method === 'POST')?.body).toEqual({
      name: 'Dana',
      role: 'developer',
    })
    expect(dialog().attributes('aria-label')).toBe('Added Dana')
    expect(dialog().text()).toContain('AAAA-BBBB-CCCC-DDDD')
    expect(dialog().text()).toContain('http://localhost:3000/sign-in#code=AAAA-BBBB-CCCC-DDDD')
    expect(router.currentRoute.value.fullPath).toBe('/people')
    expect(JSON.stringify({ ...localStorage, ...sessionStorage })).not.toContain('AAAA-BBBB')

    await button('Done').trigger('click')
    expect(dialog().exists()).toBe(false)
    expect(app.html()).not.toContain('AAAA-BBBB')
    expect(row('Dana').exists()).toBe(true)
  })

  it('says why a person was not added, and closes on Cancel', async () => {
    engine({ 'POST /people': { status: 409, body: errorBody('conflict', 'Someone is called Dana already.') } })
    ;({ app } = await openApp('/people'))

    await button('Add person…').trigger('click')
    await app.find('[role="dialog"] input').setValue('Dana')
    await app.find('[role="dialog"] form').trigger('submit')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('Someone is called Dana already.')

    await button('Cancel').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('issues a new code for someone, or says why not', async () => {
    let refuse = false
    engine({
      'POST /people/per_2/sign-in-codes': () =>
        refuse ? { status: 403, body: errorBody('forbidden', 'Not yours.') } : { status: 201, body: code },
    })
    ;({ app } = await openApp('/people'))

    await row('Dana').findAll('button').find((each) => each.text() === 'Sign-in code…')!.trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').attributes('aria-label')).toBe('Sign-in code for Dana')
    expect(app.find('[role="dialog"]').text()).toContain('AAAA-BBBB-CCCC-DDDD')
    await app.find('[role="dialog"]').trigger('keydown', { key: 'Escape' })
    expect(app.find('[role="dialog"]').exists()).toBe(false)

    refuse = true
    await row('Dana').findAll('button').find((each) => each.text() === 'Sign-in code…')!.trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('Not yours.')
  })

  it('changes a role', async () => {
    const people = [personOf(), dana]
    const seen = engine(
      {
        'PATCH /people/per_2': () => {
          people[1] = { ...dana, role: 'releaser' }
          return { status: 200, body: people[1] }
        },
      },
      people,
    )
    ;({ app } = await openApp('/people'))

    await row('Dana').find('select').setValue('releaser')
    await flushPromises()

    expect(seen.find((request) => request.method === 'PATCH')?.body).toEqual({ role: 'releaser' })
    expect((row('Dana').find('select').element as HTMLSelectElement).value).toBe('releaser')
  })

  it('says clearly why the last admin keeps their role, and shows it again', async () => {
    engine({
      'PATCH /people/per_0123456789abcdef': {
        status: 409,
        body: errorBody('conflict', 'Cannot demote Sam: they are the last admin. Make someone else an admin first.'),
      },
    })
    ;({ app } = await openApp('/people'))

    await row('Sam').find('select').setValue('developer')
    await flushPromises()

    expect(app.find('[data-testid="people-error"]').text()).toBe(
      'Cannot demote Sam: they are the last admin. Make someone else an admin first.',
    )
    expect((row('Sam').find('select').element as HTMLSelectElement).value).toBe('admin')
  })

  it('reads what the session may do again after changing its own role', async () => {
    let me = meOf()
    const people = [personOf(), personOf({ id: 'per_9', name: 'Ada' })]
    stubEngine({
      'GET /me': () => ({ status: 200, body: me }),
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /people': () => ({ status: 200, body: { people } }),
      'PATCH /people/per_0123456789abcdef': () => {
        people[0] = personOf({ role: 'releaser' })
        me = meOf('releaser', ['develop', 'decide_approval', 'release'])
        return { status: 200, body: people[0] }
      },
    })
    ;({ app } = await openApp('/people'))

    await row('Sam').find('select').setValue('releaser')
    await flushPromises()

    expect(app.find('.role').text()).toBe('releaser')
    expect(app.findAll('button').map((each) => each.text())).not.toContain('Add person…')
    expect(row('Sam').find('select').exists()).toBe(false)
  })

  it('removes a person after asking, and shows a refusal in place', async () => {
    const people = [personOf(), dana]
    engine(
      {
        'DELETE /people/per_2': () => {
          people.splice(1, 1)
          return { status: 204 }
        },
        'DELETE /people/per_0123456789abcdef': {
          status: 409,
          body: errorBody('conflict', 'Cannot remove Sam: they are the last admin. Make someone else an admin first.'),
        },
      },
      people,
    )
    ;({ app } = await openApp('/people'))

    await row('Sam').findAll('button').find((each) => each.text() === 'Remove…')!.trigger('click')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toContain('they are the last admin')
    await button('Keep').trigger('click')

    await row('Dana').findAll('button').find((each) => each.text() === 'Remove…')!.trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain('Approvals and runs keep their name.')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(row('Dana').exists()).toBe(false)
  })

  it('shows a developer the people and their roles, with nothing to change', async () => {
    stubEngine({
      'GET /me': { status: 200, body: meOf('developer', ['develop']) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /people': { status: 200, body: { people: [personOf(), dana] } },
    })
    ;({ app } = await openApp('/people'))

    expect(app.findAll('main button')).toHaveLength(0)
    expect(row('Dana').text()).toContain('developer')
  })
})
