import {
  isAlias,
  isMap,
  isScalar,
  isSeq,
  LineCounter,
  parse,
  parseDocument,
  type Document,
  type Node as YamlNode,
  type Pair,
  type YAMLMap,
} from 'yaml'

/**
 * A workflow document (`schema: 1`) as the builder edits it, the same model
 * as the Mac app's (`xp_repositories`' `WorkflowDocument`): every key the
 * engine reads, nothing it decides.
 *
 * [parseWorkflow] reads the YAML the engine reads and refuses what the model
 * cannot hold (an unknown key, a list where a mapping goes); [toYaml] writes
 * it back in the layout of the built-in workflows, so that
 * `parseWorkflow(toYaml(document))` equals `document`. Like the Mac app, the
 * YAML is what is saved: a visual edit writes the model back in that layout,
 * so comments and custom layout go with it. Whether the document is valid
 * (step types, variables, expressions) is the engine's call:
 * `POST /projects/{id}/workflows/validate`.
 */
export interface WorkflowDocument {
  /** The version of the format; `null` when the document leaves it out. */
  schema: number | null
  name: string | null
  description: string | null
  /** Whether a run holds the project (`lock: project`). */
  locksProject: boolean
  inputs: WorkflowDocumentInput[]
  stages: WorkflowStage[]
}

export type InputType = 'string' | 'boolean' | 'choice' | 'json' | 'release'

export const inputTypes: InputType[] = ['string', 'boolean', 'choice', 'json', 'release']

/** An input a dispatch can set. */
export interface WorkflowDocumentInput {
  name: string
  type: InputType | null
  description: string | null
  options: string[] | null
  /** The default; `null` when it has none. */
  defaultValue: unknown
  required: boolean
}

/** Jobs that run at the same time, after the stage before them. */
export interface WorkflowStage {
  name: string
  jobs: WorkflowJob[]
}

/** The steps one runner executes, once per cell of its matrix. */
export interface WorkflowJob {
  /** The key of the job, unique in the workflow. */
  id: string
  name: string | null
  matrix: WorkflowMatrixAxis[]
  /** The `if` a cell of the matrix must meet to make a job. */
  condition: string | null
  capabilities: string[]
  steps: WorkflowStep[]
}

/**
 * One dimension of a job's matrix: its [values] written out, or a
 * [reference] that gives them at dispatch (`${{ platforms }}`).
 */
export interface WorkflowMatrixAxis {
  name: string
  values: string[] | null
  reference: string | null
}

/** One step of a job. */
export interface WorkflowStep {
  /** The step type, for example `build.android`. */
  kind: string
  condition: string | null
  /** The action approved before the step runs. */
  gate: string | null
  /** What the step is told: plain YAML values, in their order. */
  with: Record<string, unknown>
}

/** Where the document cannot be read into the model, as the engine reports issues. */
export interface DocumentIssue {
  line: number
  column: number
  message: string
  hint?: string
}

/** The result of [parseWorkflow]: the document, or the issues that keep it from being read. */
export type ParsedWorkflow =
  | { document: WorkflowDocument; issues: [] }
  | { document: null; issues: DocumentIssue[] }

/** A document with nothing in it but its schema version. */
export function emptyDocument(): WorkflowDocument {
  return { schema: 1, name: null, description: null, locksProject: false, inputs: [], stages: [] }
}

export function emptyJob(id: string): WorkflowJob {
  return { id, name: null, matrix: [], condition: null, capabilities: [], steps: [] }
}

export function emptyStep(kind: string): WorkflowStep {
  return { kind, condition: null, gate: null, with: {} }
}

/** Reads the workflow document [source], with the line and column of each part the model cannot hold. */
export function parseWorkflow(source: string): ParsedWorkflow {
  const reader = new Reader(source)
  const document = reader.read()
  if (document === null || reader.issues.length > 0) {
    return { document: null, issues: reader.issues }
  }
  return { document, issues: [] }
}

// ------------------------------------------------------------------- reader

type Node = YamlNode | null | undefined

class Reader {
  readonly issues: DocumentIssue[] = []
  private readonly lines = new LineCounter()
  private readonly doc: Document.Parsed

  constructor(private readonly source: string) {
    this.doc = parseDocument(source, {
      lineCounter: this.lines,
      prettyErrors: false,
      uniqueKeys: true,
      logLevel: 'silent',
    })
  }

  read(): WorkflowDocument | null {
    const error = this.doc.errors[0]
    if (error) {
      this.issueAt(error.pos[0], `The document is not valid YAML: ${error.message}`)
      return null
    }
    const root = this.deref(this.doc.contents)
    if (!isMap(root)) {
      if (root) this.issue(root, 'A workflow is a mapping with "schema" and "stages".')
      else this.issueAt(0, 'A workflow is a mapping with "schema" and "stages".')
      return null
    }
    this.keys(root, 'the workflow', ['schema', 'name', 'description', 'lock', 'inputs', 'stages'])
    const schemaNode = this.get(root, 'schema')
    let schema: number | null = null
    if (isScalar(schemaNode) && Number.isInteger(schemaNode.value)) {
      schema = schemaNode.value as number
    } else if (schemaNode) {
      this.issue(schemaNode, '"schema" is a number.')
    }
    const lock = this.get(root, 'lock')
    if (lock && !(isScalar(lock) && lock.value === 'project')) {
      this.issue(lock, '"lock" can only be "project".')
    }
    return {
      schema,
      name: this.text(root, 'name'),
      description: this.text(root, 'description'),
      locksProject: lock !== null,
      inputs: this.entries(root, 'inputs').flatMap(([name, node]) => this.input(name, node) ?? []),
      stages: this.list(root, 'stages').flatMap((node) => this.stage(node) ?? []),
    }
  }

  private input(name: string, node: YamlNode): WorkflowDocumentInput | null {
    if (isScalar(node) && node.value === null) {
      return { name, type: null, description: null, options: null, defaultValue: null, required: false }
    }
    if (!isMap(node)) {
      this.issue(node, 'An input is a mapping, or empty.')
      return null
    }
    this.keys(node, `input "${name}"`, ['type', 'description', 'options', 'default', 'required'])
    const required = this.get(node, 'required')
    if (required && !(isScalar(required) && typeof required.value === 'boolean')) {
      this.issue(required, '"required" is true or false.')
    }
    const typeNode = this.get(node, 'type')
    const type = inputTypes.find((each) => isScalar(typeNode) && typeNode.value === each) ?? null
    if (typeNode && type === null) {
      this.issue(typeNode, `"type" is one of ${inputTypes.join(', ')}.`)
    }
    const optionsNode = this.get(node, 'options')
    let options: string[] | null = null
    if (optionsNode) {
      const items = isSeq(optionsNode) ? optionsNode.items.map((item) => this.deref(item as Node)) : []
      options = items.flatMap((item) => (isScalar(item) && typeof item.value === 'string' ? [item.value] : []))
      if (!isSeq(optionsNode) || options.length !== items.length) {
        this.issue(optionsNode, '"options" is a list of strings.')
      }
    }
    return {
      name,
      type,
      description: this.text(node, 'description'),
      options,
      defaultValue: this.plain(this.get(node, 'default')),
      required: isScalar(required) && required.value === true,
    }
  }

  private stage(node: YamlNode): WorkflowStage | null {
    if (!isMap(node)) {
      this.issue(node, 'A stage is a mapping with "name" and "jobs".')
      return null
    }
    this.keys(node, 'a stage', ['name', 'jobs'])
    return {
      name: this.text(node, 'name') ?? '',
      jobs: this.entries(node, 'jobs').flatMap(([id, job]) => this.job(id, job) ?? []),
    }
  }

  private job(id: string, node: YamlNode): WorkflowJob | null {
    if (!isMap(node)) {
      this.issue(node, 'A job is a mapping with "steps".')
      return null
    }
    this.keys(node, `job "${id}"`, ['name', 'matrix', 'if', 'capabilities', 'steps'])
    return {
      id,
      name: this.text(node, 'name'),
      matrix: this.entries(node, 'matrix').flatMap(([name, axis]) => this.axis(name, axis) ?? []),
      condition: this.condition(node),
      capabilities: this.strings(this.list(node, 'capabilities')),
      steps: this.list(node, 'steps').flatMap((step) => this.step(step) ?? []),
    }
  }

  private axis(name: string, node: YamlNode): WorkflowMatrixAxis | null {
    if (isScalar(node) && typeof node.value === 'string') {
      return { name, values: null, reference: node.value }
    }
    if (isSeq(node)) {
      return { name, values: this.strings(node.items.map((item) => this.deref(item as Node))), reference: null }
    }
    this.issue(node, 'A matrix axis is a list of values or a placeholder such as ${{ platforms }}.')
    return null
  }

  private step(node: YamlNode): WorkflowStep | null {
    if (!isMap(node)) {
      this.issue(node, 'A step is a mapping with a "kind".')
      return null
    }
    this.keys(node, 'a step', ['kind', 'with', 'if', 'gate'])
    const kind = this.text(node, 'kind')
    if (kind === null) this.issue(node, 'Add "kind" to the step.')
    return {
      kind: kind ?? '',
      condition: this.condition(node),
      gate: this.text(node, 'gate'),
      with: Object.fromEntries(this.entries(node, 'with').map(([key, value]) => [key, this.plain(value)])),
    }
  }

  /** The `if` of [map]. YAML reads `if: !x` as a tag on nothing; like the engine, an empty `if` is refused. */
  private condition(map: YAMLMap): string | null {
    const node = this.get(map, 'if')
    if (isScalar(node) && (node.value === null || node.value === '')) {
      this.issue(node, '"if" is empty. Quote an expression that starts with "!", as in "!flavor.prod".')
      return null
    }
    return this.text(map, 'if')
  }

  // ---------------------------------------------------------------- shapes

  private keys(map: YAMLMap, where: string, allowed: string[]) {
    for (const pair of map.items) {
      const name = this.keyOf(pair)
      if (!allowed.includes(name)) {
        this.issue((pair.key as YamlNode | null) ?? map, `Unknown key "${name}" in ${where}. Allowed: ${[...allowed].sort().join(', ')}.`)
      }
    }
  }

  private keyOf(pair: Pair): string {
    const key = this.deref(pair.key as Node)
    return isScalar(key) ? String(key.value) : String(key)
  }

  /** The node under [key], `null` when it is missing. */
  private get(map: YAMLMap, key: string): YamlNode | null {
    const pair = map.items.find((each) => this.keyOf(each) === key)
    if (!pair) return null
    return this.deref(pair.value as Node) ?? this.nullAt(pair)
  }

  /** The text under [key], `null` when it is missing or empty. */
  private text(map: YAMLMap, key: string): string | null {
    const node = this.get(map, key)
    if (node === null || (isScalar(node) && node.value === null)) return null
    if (isScalar(node) && typeof node.value === 'string') return node.value
    this.issue(node, `"${key}" is text.`)
    return null
  }

  private entries(map: YAMLMap, key: string): Array<[string, YamlNode]> {
    const node = this.get(map, key)
    if (node === null || (isScalar(node) && node.value === null)) return []
    if (!isMap(node)) {
      this.issue(node, `"${key}" is a mapping.`)
      return []
    }
    return node.items.map((pair) => [this.keyOf(pair), this.deref(pair.value as Node) ?? this.nullAt(pair)])
  }

  private list(map: YAMLMap, key: string): YamlNode[] {
    const node = this.get(map, key)
    if (node === null || (isScalar(node) && node.value === null)) return []
    if (!isSeq(node)) {
      this.issue(node, `"${key}" is a list.`)
      return []
    }
    return node.items.map((item) => this.deref(item as Node) ?? this.nullScalar(node.range?.[0] ?? 0))
  }

  private strings(nodes: Node[]): string[] {
    return nodes.flatMap((item) => {
      if (isScalar(item) && typeof item.value === 'string') return [item.value]
      if (item) this.issue(item, 'A value here is text.')
      return []
    })
  }

  // ------------------------------------------------------------- helpers

  private deref(node: Node): YamlNode | null {
    if (!node) return null
    return isAlias(node) ? ((node.resolve(this.doc) as YamlNode | undefined) ?? null) : node
  }

  /** A `null` scalar where [pair]'s value is missing (`key:` with nothing after it). */
  private nullAt(pair: Pair): YamlNode {
    const key = pair.key as YamlNode | null
    return this.nullScalar(key?.range?.[1] ?? 0)
  }

  private nullScalar(offset: number): YamlNode {
    const scalar = this.doc.createNode(null) as YamlNode
    scalar.range = [offset, offset, offset]
    return scalar
  }

  /** [node] as plain values: strings, numbers, booleans, lists and maps with text keys. */
  private plain(node: YamlNode | null): unknown {
    if (node === null) return null
    return plainOf(node.toJS(this.doc, { maxAliasCount: -1 }))
  }

  private issue(node: YamlNode, message: string) {
    this.issueAt(this.startOf(node), message)
  }

  /** Where [node] starts: at its tag when it has one (`if: !x`), as the engine says. */
  private startOf(node: YamlNode): number {
    const start = node.range?.[0] ?? 0
    if (!node.tag) return start
    const lineStart = this.source.lastIndexOf('\n', start - 1) + 1
    const tag = this.source.lastIndexOf('!', start)
    return tag >= lineStart ? tag : start
  }

  private issueAt(offset: number, message: string) {
    const { line, col } = this.lines.linePos(offset)
    this.issues.push({ line, column: col, message })
  }
}

/** [value] with maps turned into objects with text keys, as the engine reads them. */
function plainOf(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(plainOf)
  if (value instanceof Map) {
    return Object.fromEntries([...value.entries()].map(([key, item]) => [String(key), plainOf(item)]))
  }
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, plainOf(item)]))
  }
  return value
}

// ------------------------------------------------------------------- writer

/** The document as YAML, in the layout of the built-in workflows (and of the Mac app's builder). */
export function toYaml(document: WorkflowDocument): string {
  const out: string[] = []
  const root: Record<string, unknown> = {}
  if (document.schema !== null) root.schema = document.schema
  if (document.name !== null) root.name = document.name
  if (document.description !== null) root.description = document.description
  if (document.locksProject) root.lock = 'project'
  if (document.inputs.length > 0) {
    root.inputs = Object.fromEntries(document.inputs.map((input) => [input.name, plainInput(input)]))
  }
  root.stages = document.stages.map((stage) => ({
    name: stage.name,
    jobs: Object.fromEntries(stage.jobs.map((job) => [job.id, plainJob(job)])),
  }))
  writeMap(out, root, 0)
  return out.join('')
}

function plainInput(input: WorkflowDocumentInput): Record<string, unknown> {
  const plain: Record<string, unknown> = {}
  if (input.type !== null) plain.type = input.type
  if (input.description !== null) plain.description = input.description
  if (input.options !== null) plain.options = input.options
  if (input.defaultValue !== null && input.defaultValue !== undefined) plain.default = input.defaultValue
  if (input.required) plain.required = true
  return plain
}

function plainJob(job: WorkflowJob): Record<string, unknown> {
  const plain: Record<string, unknown> = {}
  if (job.name !== null) plain.name = job.name
  if (job.matrix.length > 0) {
    plain.matrix = Object.fromEntries(job.matrix.map((axis) => [axis.name, axis.values ?? axis.reference]))
  }
  if (job.condition !== null) plain.if = job.condition
  if (job.capabilities.length > 0) plain.capabilities = job.capabilities
  plain.steps = job.steps.map((step) => {
    const each: Record<string, unknown> = { kind: step.kind }
    if (step.condition !== null) each.if = step.condition
    if (step.gate !== null) each.gate = step.gate
    if (Object.keys(step.with).length > 0) each.with = step.with
    return each
  })
  return plain
}

/** [value] as one line of YAML (flow style), for a field of the builder; [parseYamlValue] reads it back. */
export function formatYamlValue(value: unknown): string {
  return typeof value === 'string' && isPlain(value) ? value : flow(value)
}

/** The plain value the YAML [text] stands for; [text] itself when it is not YAML, and `''` when blank. */
export function parseYamlValue(text: string): unknown {
  if (text.trim() === '') return ''
  const loaded = tryLoad(text)
  return loaded.ok ? plainOf(loaded.value) : text
}

/** Lists this short, of scalars, are written on one line: `[a, b]`. */
const flowWidth = 72

function isMapping(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function writeMap(out: string[], map: Record<string, unknown>, indent: number) {
  for (const [key, value] of Object.entries(map)) {
    out.push(`${' '.repeat(indent)}${keyText(key)}:`)
    writeValue(out, value, indent)
  }
}

/** Writes [value] after a `key:` (or `-`) at [indent], with its line break. */
function writeValue(out: string[], value: unknown, indent: number) {
  if (isMapping(value) && Object.keys(value).length > 0) {
    out.push('\n')
    writeMap(out, value, indent + 2)
  } else if (Array.isArray(value) && value.length > 0 && !flowable(value)) {
    out.push('\n')
    writeList(out, value, indent + 2)
  } else if (typeof value === 'string' && value.includes('\n')) {
    out.push(` ${multiline(value, indent + 2)}\n`)
  } else {
    out.push(` ${formatYamlValue(value)}\n`)
  }
}

function writeList(out: string[], list: unknown[], indent: number) {
  for (const item of list) {
    if (isMapping(item) && Object.keys(item).length > 0) {
      const [[key, value], ...rest] = Object.entries(item) as [[string, unknown], ...Array<[string, unknown]>]
      out.push(`${' '.repeat(indent)}- ${keyText(key)}:`)
      writeValue(out, value, indent + 2)
      writeMap(out, Object.fromEntries(rest), indent + 2)
    } else {
      out.push(`${' '.repeat(indent)}-`)
      writeValue(out, item, indent)
    }
  }
}

function flowable(list: unknown[]): boolean {
  return (
    list.every((item) => !isMapping(item) && !Array.isArray(item) && !(typeof item === 'string' && item.includes('\n'))) &&
    flow(list).length <= flowWidth
  )
}

function keyText(key: string): string {
  return isPlain(key) ? key : quoted(key)
}

const flowIndicator = /[,[\]{}]/

/** [value] in flow style: one line, safe inside `[...]` and `{...}`. */
function flow(value: unknown): string {
  if (value === null || value === undefined) return 'null'
  if (typeof value === 'string') {
    if (value.includes('\n') || value.includes('\r')) return JSON.stringify(value)
    return isPlain(value) && !flowIndicator.test(value) ? value : quoted(value)
  }
  if (Array.isArray(value)) return `[${value.map(flow).join(', ')}]`
  if (isMapping(value)) {
    const entries = Object.entries(value).map(([key, item]) => {
      const plain = isPlain(key) && !flowIndicator.test(key)
      return `${plain ? key : quoted(key)}: ${flow(item)}`
    })
    return `{${entries.join(', ')}}`
  }
  return String(value)
}

function quoted(text: string): string {
  return text.includes('\n') || text.includes('\r') ? JSON.stringify(text) : `'${text.replaceAll("'", "''")}'`
}

/** Whether [text] reads back as itself when written without quotes. */
function isPlain(text: string): boolean {
  if (text === '' || text.trim() !== text || /[\n\r]/.test(text)) return false
  const loaded = tryLoad(text)
  return loaded.ok && loaded.value === text
}

/** The value of the YAML [source], or that it does not parse. */
function tryLoad(source: string): { ok: true; value: unknown } | { ok: false } {
  try {
    // `logLevel: 'error'` throws on errors and keeps warnings quiet.
    return { ok: true, value: parse(source, { logLevel: 'error', mapAsMap: false }) }
  } catch {
    return { ok: false }
  }
}

/**
 * [text], which has line breaks, as a literal block (`|`) whose lines sit at
 * [indent]; JSON-style double quotes when a block cannot hold it as is.
 */
function multiline(text: string, indent: number): string {
  const body = text.endsWith('\n') ? text.slice(0, -1) : text
  const header = text.endsWith('\n') ? '|' : '|-'
  const pad = ' '.repeat(indent)
  const block = [header, ...body.split('\n').map((line) => (line === '' ? '' : `${pad}${line}`))].join('\n')
  const back = tryLoad(`x: ${block}\n`)
  return back.ok && isMapping(back.value) && back.value.x === text ? block : JSON.stringify(text)
}
