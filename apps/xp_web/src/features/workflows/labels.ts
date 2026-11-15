import type { WorkflowSchema } from '@/api/client'
import { gateAction } from '@/features/approvals/labels'

import type { Validation } from './stores/builder'

/** What the engine accepts as a workflow's name (`CreateWorkflowRequest.name`). */
export const workflowNamePattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/

/** What is wrong with [name] as a new workflow's name, or `null` when nothing is. */
export function nameProblem(name: string, taken: Iterable<string>): string | null {
  if (!workflowNamePattern.test(name)) {
    return 'Start with a letter or digit; then letters, digits, dots, dashes and underscores, 64 at most.'
  }
  return new Set(taken).has(name) ? `The project already has a workflow called ${name}.` : null
}

/** The name offered for a copy of [name]: `name-copy`, else `name-copy-2`… whichever is free. */
export function copyName(name: string, taken: Iterable<string>): string {
  const used = new Set(taken)
  const base = `${name}-copy`
  let candidate = base
  for (let n = 2; used.has(candidate); n++) candidate = `${base}-${n}`
  return candidate
}

/** What the YAML pane says of the engine's check. */
export function validationLabel(validation: Validation, issues: number): string {
  if (issues > 0 && validation !== 'checking') return issues === 1 ? '1 issue' : `${issues} issues`
  switch (validation) {
    case 'checking':
      return 'Checking…'
    case 'valid':
      return 'Valid'
    case 'unavailable':
      return 'Not checked · engine away'
    default:
      return ''
  }
}

/** What a step's gate is called: the engine's label for it, else the app's. */
export function gateLabel(gate: string, schema: WorkflowSchema | null): string {
  return schema?.gateLabels[gate] ?? gateAction(gate)
}

/** The matrix axes and platforms when the engine's schema is not known. */
export const fallbackAxes = ['platform', 'flavor']
export const fallbackPlatforms = ['android', 'ios']
