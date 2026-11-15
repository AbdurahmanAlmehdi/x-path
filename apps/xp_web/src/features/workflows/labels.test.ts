import { describe, expect, it } from 'vitest'

import { copyName, gateLabel, nameProblem, validationLabel } from './labels'

describe('the workflow labels', () => {
  it('offers a free name for a copy', () => {
    expect(copyName('dev-build', [])).toBe('dev-build-copy')
    expect(copyName('dev-build', ['dev-build-copy', 'dev-build-copy-2'])).toBe('dev-build-copy-3')
  })

  it('says what is wrong with a new name', () => {
    expect(nameProblem('nightly', ['dev-build'])).toBeNull()
    expect(nameProblem('-nightly', [])).toMatch(/^Start with a letter or digit/)
    expect(nameProblem('dev-build', ['dev-build'])).toBe('The project already has a workflow called dev-build.')
  })

  it("says what the engine's check found", () => {
    expect(validationLabel('idle', 0)).toBe('')
    expect(validationLabel('checking', 2)).toBe('Checking…')
    expect(validationLabel('valid', 0)).toBe('Valid')
    expect(validationLabel('invalid', 1)).toBe('1 issue')
    expect(validationLabel('invalid', 3)).toBe('3 issues')
    expect(validationLabel('unavailable', 0)).toBe('Not checked · engine away')
  })

  it("names a gate as the engine does, else as the app does", () => {
    const schema = { gateLabels: { prod_release: 'Production release' } } as never
    expect(gateLabel('prod_release', schema)).toBe('Production release')
    expect(gateLabel('push', schema)).toBe('push')
    expect(gateLabel('push', null)).toBe('push')
  })
})
