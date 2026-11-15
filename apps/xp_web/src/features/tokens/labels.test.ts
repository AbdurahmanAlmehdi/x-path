import { describe, expect, it } from 'vitest'

import { connectCommand, kindLabel, mcpConfig } from './labels'

describe('token labels', () => {
  it('names each kind of token as the Mac app does', () => {
    expect((['app', 'cli', 'mcp', 'runner', 'web'] as const).map(kindLabel)).toEqual([
      'Mac app',
      'xp',
      'Agent',
      'Runner',
      'Browser',
    ])
  })

  it('connects xp without the token on the command line', () => {
    expect(connectCommand('https://xpath.example.com')).toBe('xp connect https://xpath.example.com')
  })

  it('gives agents an MCP config that runs xp mcp on the engine with the token', () => {
    const config = mcpConfig('https://xpath.example.com', 'xp_mcp_secret')

    expect(JSON.parse(config)).toEqual({
      mcpServers: {
        xpath: {
          command: 'xp',
          args: ['mcp'],
          env: { XP_ENGINE_URL: 'https://xpath.example.com', XP_MCP_TOKEN: 'xp_mcp_secret' },
        },
      },
    })
    // Pretty-printed, for people who paste it into a file.
    expect(config.split('\n')[1]).toBe('  "mcpServers": {')
  })
})
