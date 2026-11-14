import { execFileSync } from 'node:child_process'
import { cpSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

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

/**
 * A git repository of the fixture app (tool/e2e/build_app) whose `origin`
 * is a bare repository at a `file://` URL, so the engine adds it without
 * GitHub (ADR 0015). Made next to the engine's data directory, which
 * web_e2e.sh removes. Returns the folder of the clone.
 */
export function fixtureRepository(name: string): string {
  const data = process.env.XPD_DATA_DIR
  if (!data) throw new Error('Run the specs with tool/e2e/web_e2e.sh.')
  const root = join(dirname(data), 'repositories', name)
  const clone = join(root, 'clone')
  const origin = join(root, 'origin.git')
  rmSync(root, { recursive: true, force: true })
  mkdirSync(root, { recursive: true })
  cpSync(fileURLToPath(new URL('../../../tool/e2e/build_app', import.meta.url)), clone, {
    recursive: true,
  })
  const git = (cwd: string, ...args: string[]) =>
    execFileSync(
      'git',
      ['-c', 'user.name=XPath e2e', '-c', 'user.email=e2e@localhost', '-c', 'commit.gpgsign=false', ...args],
      { cwd, stdio: 'ignore' },
    )
  git(clone, 'init', '--quiet', '-b', 'main')
  git(clone, 'add', '--all')
  git(clone, 'commit', '--quiet', '-m', 'fixture')
  git(root, 'clone', '--quiet', '--bare', clone, origin)
  git(clone, 'remote', 'add', 'origin', pathToFileURL(origin).href)
  return clone
}
