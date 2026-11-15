import { describe, expect, it } from 'vitest'

import { home, safeNext } from './next'

describe('safeNext', () => {
  const origin = 'http://127.0.0.1:7480'

  it.each([
    ['/runs/abc', '/runs/abc'],
    ['/runs?project=p1&status=failed', '/runs?project=p1&status=failed'],
    ['/jobs/j1#line-20', '/jobs/j1#line-20'],
    ['/', '/'],
    ['/a/../b', '/b'],
  ])('keeps the path %s on this origin', (next, path) => {
    expect(safeNext(next, origin)).toBe(path)
  })

  it.each([
    ['another site', '//evil.example'],
    ['another site with a path', '//evil.example/runs'],
    ['an absolute URL', 'https://evil.example/runs'],
    ['this origin spelled out', 'http://127.0.0.1:7480/runs'],
    ['a backslash', '/\\evil.example'],
    ['a backslash later', '/runs\\..\\x'],
    ['a scheme', 'javascript:alert(1)'],
    ['a relative path', 'runs/abc'],
    ['a tab', '/\t/evil.example'],
    ['a newline', '/runs\n'],
    ['the sign-in page', '/sign-in?next=/x'],
    ['an empty string', ''],
  ])('ignores %s', (_, next) => {
    expect(safeNext(next, origin)).toBe(home)
  })

  it('ignores what is not one string', () => {
    expect(safeNext(undefined, origin)).toBe(home)
    expect(safeNext(['/a', '/b'], origin)).toBe(home)
    expect(safeNext(null, origin)).toBe(home)
  })

  it('ignores a path the URL parser refuses', () => {
    expect(safeNext('/x', 'not an origin')).toBe(home)
  })

  it('uses the page origin by default', () => {
    expect(safeNext('/runs')).toBe('/runs')
  })
})
