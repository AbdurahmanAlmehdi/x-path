import type { CredentialKind, CredentialStatus, CredentialUsage, Project } from '@/api/client'
import type { StatusLabel } from '@/ui/format'

const kinds: Record<CredentialKind, string> = {
  asc_key: 'App Store Connect API key',
  apple_id: 'Apple ID',
  apple_distribution: 'Apple Distribution identity',
  play_sa: 'Google Play service account',
  firebase_sa: 'Firebase service account',
  keystore: 'Android keystore',
  dart_defines: 'Dart define file',
  shorebird: 'Shorebird API key',
  github: 'GitHub token',
  slack: 'Slack webhook',
}

/** What the Mac app calls a credential of [kind]. */
export function kindName(kind: CredentialKind): string {
  return kinds[kind]
}

/** The kinds a named credential can be: every kind but the engine's one GitHub token. */
export const namedKinds = (Object.keys(kinds) as CredentialKind[]).filter((kind) => kind !== 'github')

/** What a check found, as the Mac app says it. */
export function statusOf(status: CredentialStatus): StatusLabel {
  switch (status) {
    case 'verified':
      return { label: 'Verified', tone: 'positive' }
    case 'rejected':
      return { label: 'Rejected', tone: 'negative' }
    default:
      return { label: 'Not checked', tone: 'caution' }
  }
}

/** What the checks of [statuses] add up to: rejected if one is, verified if all are, `null` without any. */
export function worstStatus(statuses: CredentialStatus[]): CredentialStatus | null {
  if (statuses.length === 0) return null
  if (statuses.includes('rejected')) return 'rejected'
  return statuses.every((status) => status === 'verified') ? 'verified' : 'unverified'
}

/** How many flavors use a credential: `Not used`, `1 flavor`, `3 flavors`. */
export function usedByLabel(count: number): string {
  if (count === 0) return 'Not used'
  return count === 1 ? '1 flavor' : `${count} flavors`
}

/** Where a credential is used: the project, the app (when not the root one) and the flavor. */
export function usageLabel(usage: CredentialUsage): string {
  return [usage.project ?? usage.projectId, usage.app === '.' ? undefined : usage.app, usage.flavor]
    .filter(Boolean)
    .join(' · ')
}

/** A flavor of an app of a project, as an assignment addresses it. */
export interface FlavorTarget {
  app: string
  appName: string
  flavor: string
  /** Whether its app has an iOS app, which signs with an Apple Distribution identity. */
  hasIos: boolean
}

/** The flavors of [project], `default` for an app without flavors. */
export function flavorTargets(project: Project): FlavorTarget[] {
  return project.profile.apps.flatMap((app) => {
    const target = { app: app.path, appName: app.name, hasIos: app.hasIos }
    return app.flavors.length === 0
      ? [{ ...target, flavor: 'default' }]
      : app.flavors.map((flavor) => ({ ...target, flavor: flavor.name }))
  })
}

/** The longest name a credential may have. */
const nameLimit = 80

/**
 * The name of the Apple Distribution identity the engine creates for
 * [flavor] of [project], as the Mac app names it. A project on the engine's
 * machine is named by its folder, so a name too long for a credential keeps
 * only the folder's last part, and is cut there if it must be.
 */
export function certificateName(project: string, flavor: string): string {
  const name = `Apple Distribution · ${project} ${flavor}`
  if (name.length <= nameLimit) return name
  return `Apple Distribution · ${project.split('/').pop()} ${flavor}`.slice(0, nameLimit)
}

/** How a secret field of a kind is filled. */
export type FieldInput = 'text' | 'secret' | 'textFile' | 'binaryFile'

/** A secret field of a kind, named as the API reads it. */
export interface SecretField {
  name: string
  label: string
  input: FieldInput
  /** The files the picker offers. */
  accept?: string
  optional?: boolean
}

/**
 * The secret fields of each named kind (`openapi.yaml`, `*Fields`). A key
 * file goes from the file picker to the engine as it is: the page never
 * shows what is in it.
 */
export const secretFields: Record<Exclude<CredentialKind, 'github'>, SecretField[]> = {
  asc_key: [
    { name: 'keyId', label: 'Key ID', input: 'text' },
    { name: 'issuerId', label: 'Issuer ID', input: 'text' },
    { name: 'privateKey', label: 'Private key (.p8)', input: 'textFile', accept: '.p8' },
  ],
  apple_id: [
    { name: 'appleId', label: 'Apple ID', input: 'text' },
    { name: 'password', label: 'App-specific password', input: 'secret' },
  ],
  apple_distribution: [
    { name: 'privateKey', label: 'Private key (PEM)', input: 'textFile', accept: '.pem,.key' },
    { name: 'certificate', label: 'Certificate (.cer)', input: 'binaryFile', accept: '.cer,.crt,.pem' },
  ],
  play_sa: [{ name: 'serviceAccount', label: 'Service account key (JSON)', input: 'textFile', accept: '.json' }],
  firebase_sa: [{ name: 'serviceAccount', label: 'Service account key (JSON)', input: 'textFile', accept: '.json' }],
  keystore: [
    { name: 'keystore', label: 'Keystore', input: 'binaryFile', accept: '.jks,.keystore,.p12' },
    { name: 'storePassword', label: 'Store password', input: 'secret' },
    { name: 'keyAlias', label: 'Key alias', input: 'text' },
    { name: 'keyPassword', label: 'Key password (if not the store password)', input: 'secret', optional: true },
  ],
  dart_defines: [
    {
      name: 'dartDefines',
      label: 'Dart define file (JSON or KEY=value lines)',
      input: 'textFile',
      accept: '.json,.env,.txt',
    },
  ],
  shorebird: [{ name: 'token', label: 'Token', input: 'secret' }],
  slack: [{ name: 'webhookUrl', label: 'Webhook URL', input: 'secret' }],
}

/** [bytes] as base64, as the API reads a binary file. */
export function base64Of(bytes: ArrayBuffer): string {
  const view = new Uint8Array(bytes)
  let binary = ''
  for (let start = 0; start < view.length; start += 0x8000) {
    binary += String.fromCharCode(...view.subarray(start, start + 0x8000))
  }
  return btoa(binary)
}
