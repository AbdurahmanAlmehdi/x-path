// Fails when a package in package-lock.json has a license outside the list
// below, or none. npm records each package's `license` in the lock file, so
// this needs no network and no extra dependency.
import { readFileSync } from 'node:fs'

const allowed = new Set([
  '0BSD',
  'Apache-2.0',
  'BlueOak-1.0.0',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'CC-BY-4.0',
  'CC0-1.0',
  'ISC',
  'MIT',
  'MPL-2.0',
  'Python-2.0',
])

// An SPDX expression passes when every alternative of an OR, or every
// part of an AND, is allowed: `(MIT OR CC0-1.0)` needs one, `(MIT AND
// Zlib)` both.
function passes(expression) {
  const bare = expression.replace(/^\((.*)\)$/, '$1').trim()
  if (bare.includes(' OR ')) return bare.split(' OR ').some(passes)
  if (bare.includes(' AND ')) return bare.split(' AND ').every(passes)
  return allowed.has(bare)
}

const lock = JSON.parse(readFileSync(new URL('../package-lock.json', import.meta.url)))
const refused = []
for (const [path, entry] of Object.entries(lock.packages ?? {})) {
  if (path === '' || entry.link) continue
  const license = typeof entry.license === 'string' ? entry.license : null
  if (license === null || !passes(license)) {
    refused.push(`${path.replace(/^.*node_modules\//, '')}@${entry.version}: ${license ?? 'no license'}`)
  }
}

if (refused.length > 0) {
  console.error(`Licenses outside the allowed list:\n  ${refused.join('\n  ')}`)
  process.exit(1)
}
console.log(`Checked the licenses of ${Object.keys(lock.packages).length - 1} packages.`)
