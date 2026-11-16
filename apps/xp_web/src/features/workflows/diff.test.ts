import { describe, expect, it } from 'vitest'

import { diffLines } from './diff'

describe('diffLines', () => {
  it('keeps the lines both texts have, and marks what was removed before what was added', () => {
    expect(diffLines('a\nb\nc\n', 'a\nx\nc\n')).toEqual([
      { kind: 'same', text: 'a' },
      { kind: 'removed', text: 'b' },
      { kind: 'added', text: 'x' },
      { kind: 'same', text: 'c' },
    ])
  })

  it('reads a text without a last line break as one with it', () => {
    expect(diffLines('a\nb', 'a\nb\n')).toEqual([
      { kind: 'same', text: 'a' },
      { kind: 'same', text: 'b' },
    ])
  })

  it('takes an empty text as no lines', () => {
    expect(diffLines('', 'a\n')).toEqual([{ kind: 'added', text: 'a' }])
    expect(diffLines('a\n', '')).toEqual([{ kind: 'removed', text: 'a' }])
    expect(diffLines('', '')).toEqual([])
  })

  it('finds the longest run in common', () => {
    expect(diffLines('x\na\nb\n', 'a\nb\ny\n').map((line) => `${line.kind[0]}${line.text}`)).toEqual([
      'rx',
      'sa',
      'sb',
      'ay',
    ])
  })
})
