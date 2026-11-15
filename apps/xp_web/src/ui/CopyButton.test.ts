import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'

import CopyButton from './CopyButton.vue'

describe('CopyButton', () => {
  afterEach(() => vi.useRealTimers())

  function withClipboard(writeText: (text: string) => Promise<void>) {
    vi.stubGlobal('navigator', { ...navigator, clipboard: { writeText } })
  }

  it('copies, says so for a moment, then shows its label again', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    const writeText = vi.fn(async () => {})
    withClipboard(writeText)
    const button = mount(CopyButton, { props: { label: 'Copy link', text: 'https://example.test' } })

    await button.trigger('click')
    await flushPromises()
    expect(writeText).toHaveBeenCalledWith('https://example.test')
    expect(button.text()).toBe('Copied')

    vi.advanceTimersByTime(1200)
    await flushPromises()
    expect(button.text()).toBe('Copy link')
    button.unmount()
  })

  it('says nothing was copied when the browser refuses the clipboard', async () => {
    withClipboard(async () => {
      throw new Error('Denied.')
    })
    const button = mount(CopyButton, { props: { label: 'Copy link', text: 'x' } })

    await button.trigger('click')
    await flushPromises()

    expect(button.text()).toBe('Copy link')
  })
})
