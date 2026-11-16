import { afterEach, describe, expect, it, vi } from 'vitest'

import { saveText } from './download'

describe('saveText', () => {
  // jsdom has no object URLs.
  const { createObjectURL, revokeObjectURL } = URL
  afterEach(() => {
    vi.useRealTimers()
    URL.createObjectURL = createObjectURL
    URL.revokeObjectURL = revokeObjectURL
  })

  it('clicks a link to the text as a file of that name, and lets the address go after', async () => {
    vi.useFakeTimers()
    const created: Blob[] = []
    URL.createObjectURL = (blob: Blob) => {
      created.push(blob)
      return 'blob:file'
    }
    const revoked = vi.fn()
    URL.revokeObjectURL = revoked
    const clicked: HTMLAnchorElement[] = []
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      clicked.push(this)
    })

    saveText('nightly.yaml', 'schema: 1\n', 'application/yaml')

    expect(clicked).toHaveLength(1)
    expect(clicked[0]!.download).toBe('nightly.yaml')
    expect(clicked[0]!.href).toBe('blob:file')
    expect(created[0]!.type).toBe('application/yaml')
    expect(await created[0]!.text()).toBe('schema: 1\n')
    expect(revoked).not.toHaveBeenCalled()
    vi.runAllTimers()
    expect(revoked).toHaveBeenCalledWith('blob:file')
  })
})
