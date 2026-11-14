import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { personOf } from '@/testing/fixtures'

import { usePeopleStore } from './people'

describe('usePeopleStore', () => {
  beforeEach(() => setActivePinia(createPinia()))

  const dana = personOf({ id: 'per_2', name: 'Dana', role: 'developer' })

  it('loads the people, active and removed apart, and names them', async () => {
    stubEngine({
      'GET /people': {
        status: 200,
        body: { people: [personOf(), dana, personOf({ id: 'per_3', name: 'Gone', removedAt: '2026-11-14T10:00:00Z' })] },
      },
    })
    const store = usePeopleStore()

    await store.load()

    expect(store.active.map((person) => person.name)).toEqual(['Sam', 'Dana'])
    expect(store.removed.map((person) => person.name)).toEqual(['Gone'])
    expect(store.nameOf('per_2')).toBe('Dana')
    expect(store.nameOf('per_9')).toBe('per_9')
    expect(store.nameOf(undefined)).toBe('')
  })

  it('says why the people could not be read', async () => {
    stubUnreachableEngine()
    const store = usePeopleStore()

    await store.load()

    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('adds a person and loads again', async () => {
    const seen = stubEngine({
      'POST /people': { status: 201, body: dana },
      'GET /people': { status: 200, body: { people: [personOf(), dana] } },
    })
    const store = usePeopleStore()

    const added = await store.add(' Dana ', 'developer')

    expect(added.id).toBe('per_2')
    expect(seen[0]?.body).toEqual({ name: 'Dana', role: 'developer' })
    expect(store.active).toHaveLength(2)
  })

  it('throws the refusal of a new person', async () => {
    stubEngine({ 'POST /people': { status: 409, body: errorBody('conflict', 'Dana is taken.') } })

    await expect(usePeopleStore().add('Dana', 'viewer')).rejects.toThrow('Dana is taken.')
  })

  it('changes a role, and keeps the last admin’s 409 for the page to show', async () => {
    const seen = stubEngine({
      'PATCH /people/per_2': { status: 200, body: { ...dana, role: 'viewer' } },
      'PATCH /people/per_0123456789abcdef': {
        status: 409,
        body: errorBody('conflict', 'Cannot demote Sam: they are the last admin. Make someone else an admin first.'),
      },
      'GET /people': { status: 200, body: { people: [personOf(), { ...dana, role: 'viewer' }] } },
    })
    const store = usePeopleStore()

    expect(await store.setRole('per_2', 'viewer')).toBe(true)
    expect(seen[0]?.body).toEqual({ role: 'viewer' })
    expect(store.active[1]?.role).toBe('viewer')

    expect(await store.setRole('per_0123456789abcdef', 'developer')).toBe(false)
    expect(store.actionError).toBe(
      'Cannot demote Sam: they are the last admin. Make someone else an admin first.',
    )
    expect(store.changing).toBeNull()
  })

  it('removes a person', async () => {
    stubEngine({
      'DELETE /people/per_2': { status: 204 },
      'GET /people': { status: 200, body: { people: [personOf()] } },
    })
    const store = usePeopleStore()

    expect(await store.remove('per_2')).toBe(true)
    expect(store.active).toHaveLength(1)
  })

  it('hands a sign-in code to the caller and keeps none', async () => {
    stubEngine({
      'POST /people/per_2/sign-in-codes': {
        status: 201,
        body: { code: 'AAAA-BBBB-CCCC-DDDD', personId: 'per_2', expiresAt: '2026-11-14T09:10:00Z' },
      },
    })
    const store = usePeopleStore()

    const code = await store.signInCode('per_2')

    expect(code.code).toBe('AAAA-BBBB-CCCC-DDDD')
    expect(JSON.stringify(store.$state)).not.toContain('AAAA-BBBB')
  })
})
