import { execFileSync } from 'node:child_process'

/**
 * The engine tool/e2e/web_e2e.sh started: `xpd person` on its data
 * directory, as an admin on the engine machine runs it.
 */
function xpd(...args: string[]): string {
  const bin = process.env.XPD_BIN
  const data = process.env.XPD_DATA_DIR
  if (!bin || !data) throw new Error('Run the specs with tool/e2e/web_e2e.sh.')
  return execFileSync(bin, ['person', ...args, '--data-dir', data], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim()
}

/** Adds a person with [role]; returns their id. */
export function createPerson(name: string, role: 'viewer' | 'developer' | 'releaser' | 'admin') {
  return xpd('create', '--name', name, '--role', role)
}

/** A new one-time sign-in code of [name]. */
export function signInCode(name: string): string {
  return xpd('code', name)
}
