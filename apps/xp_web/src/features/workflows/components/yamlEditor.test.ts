import { EditorView } from '@codemirror/view'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { createYamlEditor, type YamlEditorHandle } from './yamlEditor'

describe('createYamlEditor', () => {
  let host: HTMLElement
  let editor: YamlEditorHandle | undefined

  afterEach(() => {
    editor?.destroy()
    host.remove()
  })

  function mount(text: string, readOnly = false) {
    host = document.createElement('div')
    document.body.append(host)
    const onChange = vi.fn()
    editor = createYamlEditor(host, { text, readOnly, label: 'YAML', onChange })
    const content = () => host.shadowRoot!.querySelector<HTMLElement>('.cm-content')!
    return { onChange, content }
  }

  it('shows the text in a shadow root, labelled, and editable unless read-only', () => {
    const { content } = mount('schema: 1\n')

    expect(host.shadowRoot).not.toBeNull()
    expect(content().textContent).toBe('schema: 1')
    expect(content().getAttribute('aria-label')).toBe('YAML')
    expect(content().getAttribute('contenteditable')).toBe('true')

    editor!.setReadOnly(true)
    expect(content().getAttribute('contenteditable')).toBe('false')
  })

  it('takes text from the page without telling it, changing only what differs', () => {
    const { onChange, content } = mount('name: a\nstages: []\n')

    editor!.setText('name: b\nstages: []\n')
    editor!.setText('name: b\nstages: []\n')

    expect(content().textContent).toBe('name: bstages: []')
    expect(onChange).not.toHaveBeenCalled()
  })

  it('tells the page what is typed', () => {
    const { onChange } = mount('name: a\n')
    const view = EditorView.findFromDOM(host.shadowRoot!.querySelector<HTMLElement>('.cm-editor')!)!

    view.dispatch({ changes: { from: 6, to: 7, insert: 'b' }, userEvent: 'input.type' })

    expect(onChange).toHaveBeenCalledWith('name: b\n')
  })

  it('marks issues on their lines and reveals one', () => {
    // jsdom has no execCommand, which CodeMirror reads the selection of a shadow root with.
    Object.defineProperty(document, 'execCommand', { value: () => false, configurable: true })
    const { content } = mount('schema: 1\nstages:\n  - x\n')

    editor!.setIssues([
      { line: 3, column: 5, message: 'A stage is a mapping.' },
      { line: 9, column: 99, message: 'Past the end.' },
    ])
    editor!.reveal(3, 5)

    expect(host.shadowRoot!.querySelectorAll('.cm-lint-marker-error').length).toBeGreaterThan(0)
    expect(content().querySelector('.cm-activeLine')?.textContent).toBe('  - x')
  })
})
