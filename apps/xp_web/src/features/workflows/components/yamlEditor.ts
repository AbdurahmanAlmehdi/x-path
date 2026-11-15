import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands'
import { yaml } from '@codemirror/lang-yaml'
import { HighlightStyle, indentUnit, syntaxHighlighting } from '@codemirror/language'
import { lintGutter, setDiagnostics, type Diagnostic } from '@codemirror/lint'
import { Annotation, Compartment, EditorState } from '@codemirror/state'
import { EditorView, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from '@codemirror/view'
import { tags } from '@lezer/highlight'

// CodeMirror 6, loaded only when a page shows the YAML editor: the router
// loads the workflows page lazily, and that page imports this module with a
// dynamic `import()`, so none of it is in the entry chunk (e2e/workflows.spec.ts).
//
// The dashboard's CSP is `style-src 'self'`: no `<style>` element may apply.
// CodeMirror (style-mod) writes its styles into a `<style>` element in a
// document, but into a constructable style sheet (`adoptedStyleSheets`) in a
// shadow root, which the CSP does not govern. So the editor lives in a shadow
// root of its host, and its look is a CodeMirror theme on the design tokens,
// whose custom properties reach into the shadow root. Nothing here needs
// `unsafe-eval` or a change to the CSP.

/** An issue to mark: 1-based line and column, as the engine and the model give them. */
export interface EditorIssue {
  line: number
  column: number
  message: string
}

/** What the page drives the editor with. */
export interface YamlEditorHandle {
  /** Replaces the text, changing only what differs, as an edit [onChange] does not hear. */
  setText(text: string): void
  setReadOnly(readOnly: boolean): void
  /** Marks [issues] in the gutter and under their text. */
  setIssues(issues: EditorIssue[]): void
  /** Puts the cursor at [line] and [column], scrolls it into view and focuses the editor. */
  reveal(line: number, column: number): void
  destroy(): void
}

interface YamlEditorOptions {
  text: string
  readOnly: boolean
  /** The accessible name of the text area. */
  label: string
  /** Called with the text after each change typed in the editor. */
  onChange(text: string): void
}

/** The colors of the design's code tokens, light and dark. */
const highlight = HighlightStyle.define([
  { tag: [tags.propertyName, tags.definition(tags.propertyName)], color: 'var(--xp-color-code-key)' },
  { tag: [tags.string, tags.special(tags.string), tags.content], color: 'var(--xp-color-code-string)' },
  { tag: [tags.number, tags.bool, tags.null], color: 'var(--xp-color-code-number)' },
  { tag: [tags.keyword, tags.typeName, tags.labelName, tags.meta], color: 'var(--xp-color-code-keyword)' },
  { tag: [tags.comment, tags.lineComment], color: 'var(--xp-color-code-comment)', fontStyle: 'italic' },
  { tag: tags.invalid, color: 'var(--xp-color-code-error)' },
])

/** The editor on the design tokens, light and dark. */
const theme = EditorView.theme({
  '&': {
    minHeight: '320px',
    maxHeight: '70vh',
    color: 'var(--xp-color-code-text)',
    backgroundColor: 'var(--xp-color-code-surface)',
    border: 'var(--xp-border-width-hairline) solid var(--xp-color-border-strong)',
    borderRadius: 'var(--xp-radius-md)',
  },
  '&.cm-focused': {
    outline: 'var(--xp-border-width-focus) solid var(--xp-color-focus-ring)',
  },
  '.cm-scroller': { font: 'var(--xp-type-code)' },
  '.cm-gutters': {
    color: 'var(--xp-color-code-gutter)',
    backgroundColor: 'var(--xp-color-code-surface)',
    borderRight: 'var(--xp-border-width-hairline) solid var(--xp-color-border-subtle)',
  },
  '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: 'var(--xp-color-surface-hover)' },
  '.cm-content': { caretColor: 'var(--xp-color-text-primary)' },
  '.cm-cursor, .cm-dropCursor': { borderLeftColor: 'var(--xp-color-text-primary)' },
  '&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground': {
    backgroundColor: 'var(--xp-color-selection-default)',
  },
  '.cm-tooltip': {
    color: 'var(--xp-color-text-primary)',
    backgroundColor: 'var(--xp-color-surface-overlay)',
    border: 'var(--xp-border-width-hairline) solid var(--xp-color-border-strong)',
  },
})

/** Marks a change made by the page, not typed. */
const fromPage = Annotation.define<boolean>()

/** Mounts a YAML editor in a shadow root of [host]. */
export function createYamlEditor(host: HTMLElement, options: YamlEditorOptions): YamlEditorHandle {
  const root = host.shadowRoot ?? host.attachShadow({ mode: 'open' })
  const parent = document.createElement('div')
  root.append(parent)
  const editing = new Compartment()
  const editable = (readOnly: boolean) => [EditorState.readOnly.of(readOnly), EditorView.editable.of(!readOnly)]

  const view = new EditorView({
    parent,
    root,
    state: EditorState.create({
      doc: options.text,
      extensions: [
        lineNumbers(),
        lintGutter(),
        history(),
        highlightActiveLine(),
        highlightActiveLineGutter(),
        indentUnit.of('  '),
        EditorState.tabSize.of(2),
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        yaml(),
        syntaxHighlighting(highlight),
        theme,
        editing.of(editable(options.readOnly)),
        EditorView.contentAttributes.of({ 'aria-label': options.label, 'data-testid': 'yaml-editor' }),
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !update.transactions.some((each) => each.annotation(fromPage))) {
            options.onChange(update.state.doc.toString())
          }
        }),
      ],
    }),
  })

  function positionOf(line: number, column: number): number {
    const doc = view.state.doc
    const at = doc.line(Math.min(Math.max(line, 1), doc.lines))
    return Math.min(at.from + Math.max(column, 1) - 1, at.to)
  }

  return {
    setText(text) {
      const current = view.state.doc.toString()
      if (text === current) return
      let start = 0
      while (start < current.length && start < text.length && current[start] === text[start]) start++
      let end = 0
      while (
        end < current.length - start &&
        end < text.length - start &&
        current[current.length - 1 - end] === text[text.length - 1 - end]
      ) {
        end++
      }
      view.dispatch({
        changes: { from: start, to: current.length - end, insert: text.slice(start, text.length - end) },
        annotations: fromPage.of(true),
      })
    },
    setReadOnly(readOnly) {
      view.dispatch({ effects: editing.reconfigure(editable(readOnly)) })
    },
    setIssues(issues) {
      const diagnostics: Diagnostic[] = issues.map((issue) => {
        const from = positionOf(issue.line, issue.column)
        const to = view.state.doc.lineAt(from).to
        return { from, to: Math.max(to, from), severity: 'error', message: issue.message }
      })
      view.dispatch(setDiagnostics(view.state, diagnostics))
    },
    reveal(line, column) {
      const at = positionOf(line, column)
      view.dispatch({ selection: { anchor: at }, effects: EditorView.scrollIntoView(at, { y: 'center' }) })
      view.focus()
    },
    destroy() {
      view.destroy()
      parent.remove()
    },
  }
}
