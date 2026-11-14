import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { personOf, tokenOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

describe('TokensView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, admin = true) {
    return stubEngine({
      'GET /me': { status: 200, body: admin ? meOf() : meOf('viewer', []) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /people': {
        status: 200,
        body: { people: [personOf(), personOf({ id: 'per_2', name: 'Dana', role: 'developer' })] },
      },
      'GET /tokens': {
        status: 200,
        body: {
          tokens: [
            tokenOf({ id: 'tok_0123456789abcdef', name: 'Browser', kind: 'web' }),
            tokenOf(),
            tokenOf({ id: 'tok_4', name: 'Dana’s agent', kind: 'mcp', personId: 'per_2' }),
          ],
        },
      },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  it('lists the tokens with their kind and, for an admin, their person', async () => {
    engine()
    ;({ app } = await openApp('/tokens'))

    const rows = app.findAll('[data-testid="tokens"] tbody tr')
    expect(rows.map((row) => row.findAll('td').map((cell) => cell.text()).slice(0, 3))).toEqual([
      ['Browser', 'Browser', 'Sam'],
      ['xp on my laptop', 'xp', 'Sam'],
      ['Dana’s agent', 'Agent', 'Dana'],
    ])
    expect(rows[0]!.text()).toContain('This browser')
  })

  it('shows a new xp token once with the command, and forgets it on Done', async () => {
    const seen = engine({
      'POST /tokens': { status: 201, body: { info: tokenOf({ id: 'tok_5', name: 'xp on ci' }), token: 'xpt_fake_cli' } },
    })
    ;({ app } = await openApp('/tokens'))

    await button('New xp token').trigger('click')
    await app.find('[role="dialog"] input').setValue('xp on ci')
    await button('Make token').trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.method === 'POST')?.body).toEqual({ name: 'xp on ci', kind: 'cli' })
    const dialog = app.find('[role="dialog"]')
    expect(dialog.attributes('aria-label')).toBe('Made “xp on ci”')
    expect(dialog.text()).toContain('xp connect http://localhost:3000')
    expect(dialog.text()).toContain('xpt_fake_cli')
    expect(dialog.text()).toContain('The token is shown this once.')

    await button('Done').trigger('click')
    expect(app.html()).not.toContain('xpt_fake_cli')
  })

  it('shows a new agent token in its MCP config', async () => {
    engine({
      'POST /tokens': { status: 201, body: { info: tokenOf({ kind: 'mcp', name: 'Agent' }), token: 'xpt_fake_mcp' } },
    })
    ;({ app } = await openApp('/tokens'))

    await button('New agent token').trigger('click')
    expect((app.find('[role="dialog"] input').element as HTMLInputElement).value).toBe('Agent on my laptop')
    await app.find('[role="dialog"] form').trigger('submit')
    await flushPromises()

    expect(app.find('[role="dialog"]').text()).toContain('"XP_MCP_TOKEN": "xpt_fake_mcp"')
    expect(app.find('[role="dialog"]').text()).toContain('"XP_ENGINE_URL": "http://localhost:3000"')
  })

  it('says why a token was refused, and closes on Cancel', async () => {
    engine({ 'POST /tokens': { status: 400, body: errorBody('invalid_request', 'The name is empty.') } })
    ;({ app } = await openApp('/tokens'))

    await button('New xp token').trigger('click')
    await button('Make token').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('The name is empty.')

    await button('Cancel').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('revokes a token after asking, and shows a refusal in place', async () => {
    let revoked = false
    engine(
      {
        'GET /tokens': () => ({ status: 200, body: { tokens: revoked ? [] : [tokenOf(), tokenOf({ id: 'tok_9', name: 'gone' })] } }),
        'DELETE /tokens/tok_2': () => {
          revoked = true
          return { status: 204 }
        },
        'DELETE /tokens/tok_9': { status: 404, body: errorBody('not_found', 'No such token.') },
      },
      false,
    )
    ;({ app } = await openApp('/tokens'))
    expect(app.find('[data-testid="tokens"] thead').text()).not.toContain('Person')

    await app.findAll('[data-testid="tokens"] tbody tr')[1]!.find('button').trigger('click')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('No such token.')
    await button('Keep').trigger('click')

    await app.findAll('[data-testid="tokens"] tbody tr')[0]!.find('button').trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain('It stops working at once')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(app.findAll('[data-testid="tokens"] tbody tr')).toHaveLength(0)
  })
})
