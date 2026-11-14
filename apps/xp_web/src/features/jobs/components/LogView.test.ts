import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { FakeSocket, stubSockets } from '@/testing/sockets'

import { useJobLogStore } from '../stores/log'
import LogView from './LogView.vue'

const line = (seq: number) => ({
  type: 'line',
  seq,
  step: 0,
  at: '2026-11-14T09:00:00Z',
  stream: 'stdout',
  text: `line ${seq}`,
})

/** Gives the log box the sizes a browser would. */
function size(element: Element, scrollHeight: number, clientHeight: number) {
  Object.defineProperty(element, 'scrollHeight', { configurable: true, value: scrollHeight })
  Object.defineProperty(element, 'clientHeight', { configurable: true, value: clientHeight })
}

describe('LogView', () => {
  let socket: FakeSocket

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
    useJobLogStore().follow('job_2')
    socket = FakeSocket.last().open()
  })

  async function receive(seq: number) {
    socket.send(line(seq))
    await flushPromises()
  }

  it('shows each line as it arrives, and keeps the newest in sight while it follows', async () => {
    const view = mount(LogView)
    expect(view.find('.empty').text()).toBe('No output yet')
    const box = view.find('.log').element as HTMLElement
    size(box, 1000, 200)

    await receive(1)
    await receive(2)

    expect(view.findAll('.line .text').map((text) => text.text())).toEqual(['line 1', 'line 2'])
    expect(view.find('[data-testid="log-count"]').text()).toBe('2 lines · live')
    expect(box.scrollTop).toBe(1000)
    expect(view.find('button').attributes('aria-pressed')).toBe('true')
  })

  it('stops following when scrolled up, and follows again on Follow', async () => {
    const view = mount(LogView)
    await receive(1)
    const box = view.find('.log').element as HTMLElement
    size(box, 1000, 200)
    box.scrollTop = 100

    await view.find('.log').trigger('scroll')
    await receive(2)
    expect(view.find('button').attributes('aria-pressed')).toBe('false')
    expect(box.scrollTop).toBe(100)

    await view.find('button').trigger('click')
    expect(view.find('button').attributes('aria-pressed')).toBe('true')
    expect(box.scrollTop).toBe(1000)
  })

  it('selects the text of the lines, not their numbers', async () => {
    const view = mount(LogView)
    await receive(7)
    socket.send({ type: 'end', state: 'succeeded' })
    await flushPromises()

    expect(view.find('.gutter').attributes('aria-hidden')).toBe('true')
    expect(view.find('.line').attributes('data-seq')).toBe('7')
    expect(view.find('[data-testid="log-count"]').text()).toBe('1 line')
  })
})
