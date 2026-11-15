import type { TokenInfo } from '@/api/client'

const kinds: Record<TokenInfo['kind'], string> = {
  app: 'Mac app',
  cli: 'xp',
  mcp: 'Agent',
  runner: 'Runner',
  web: 'Browser',
}

/** What a token of [kind] is for. */
export function kindLabel(kind: TokenInfo['kind']): string {
  return kinds[kind]
}

/**
 * The command that connects `xp` to the engine at [url]. It asks for the
 * token, so the token stays out of the shell history.
 */
export function connectCommand(url: string): string {
  return `xp connect ${url}`
}

/** The MCP config that runs `xp mcp` on the engine at [url] with [token], as agents read it. */
export function mcpConfig(url: string, token: string): string {
  return JSON.stringify(
    {
      mcpServers: {
        xpath: { command: 'xp', args: ['mcp'], env: { XP_ENGINE_URL: url, XP_MCP_TOKEN: token } },
      },
    },
    null,
    2,
  )
}
