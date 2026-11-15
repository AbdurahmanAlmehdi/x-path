import { describe, expect, it } from 'vitest'

import {
  emptyDocument,
  formatYamlValue,
  parseWorkflow,
  parseYamlValue,
  toYaml,
  type DocumentIssue,
  type WorkflowDocument,
  type WorkflowDocumentInput,
  type WorkflowJob,
  type WorkflowStep,
} from './document'

// The cases of the Mac app's `workflow_document_test.dart`, so both builders
// read and write the same YAML.

/** The engine's built-in `dev-build`, as the engine ships it. */
const devBuild = `schema: 1
name: Dev build
description: >-
  Builds the dev flavors and sends them to testers: Android to Firebase App
  Distribution, iOS to TestFlight.
inputs:
  firebaseAppIds:
    description: >-
      Firebase app ids by flavor and platform, for example
      {dev: {android: "1:123456789012:android:abcdef"}}. A build without one
      is not uploaded.
  testerGroups:
    description: Firebase tester group aliases.
    default: []
  notes:
    description: Release notes for the testers.
    default: ""
stages:
  - name: check
    jobs:
      check:
        name: Check \${{ flavor.name }} for \${{ platform }}
        matrix:
          platform: \${{ platforms }}
          flavor: \${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials]
  - name: upload
    jobs:
      upload:
        name: Upload \${{ flavor.name }} for \${{ platform }}
        matrix:
          platform: \${{ platforms }}
          flavor: \${{ flavors }}
        if: >-
          (platform == 'android' && inputs.firebaseAppIds[flavor.name].android)
          || (platform == 'ios' && inputs.appleAppIds[flavor.name])
        steps:
          - kind: upload.firebase
            if: platform == 'android' && inputs.firebaseAppIds[flavor.name].android
            with:
              artifactsFrom: build
              groupAliases: \${{ inputs.testerGroups }}
`

function input(fields: Partial<WorkflowDocumentInput> & { name: string }): WorkflowDocumentInput {
  return { type: null, description: null, options: null, defaultValue: null, required: false, ...fields }
}

function job(fields: Partial<WorkflowJob> & { id: string }): WorkflowJob {
  return { name: null, matrix: [], condition: null, capabilities: [], steps: [], ...fields }
}

function step(fields: Partial<WorkflowStep> & { kind: string }): WorkflowStep {
  return { condition: null, gate: null, with: {}, ...fields }
}

// A key that reads as a whole number goes first in a JavaScript object, so
// `'1'` leads `with` here where the Mac app's test has it later.
const rich: WorkflowDocument = {
  schema: 1,
  name: 'Dev build',
  description: 'Line one\nline two\n',
  locksProject: true,
  inputs: [
    input({ name: 'notes', description: 'Notes', defaultValue: '' }),
    input({ name: 'plain' }),
    input({ name: 'need', required: true }),
  ],
  stages: [
    {
      name: 'build',
      jobs: [
        job({
          id: 'build',
          name: 'Build ${{ flavor.name }} for ${{ platform }}',
          matrix: [
            { name: 'platform', values: null, reference: '${{ platforms }}' },
            { name: 'flavor', values: ['prod', 'dev'], reference: null },
          ],
          condition: "platform == 'android'",
          capabilities: ['flutter'],
          steps: [
            step({ kind: 'git.checkout' }),
            step({
              kind: 'command',
              condition: '!flavor.prod',
              gate: 'push',
              with: {
                '1': 'key: value',
                run: 'echo a\necho b',
                n: 1,
                ratio: 0.5,
                on: false,
                nothing: null,
                yes: 'true',
                list: ['a,b', '${{ x }}', 3],
                maps: [{ a: 1, b: { c: 'd' } }, [1, 2], 'x\ny', []],
                empty: {},
                odd: '\n  indented',
                carriage: 'a\rb',
                trailing: 'a\n\n',
                'line\nkey': 1,
                long: ['aaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbb', 'cccccccccccccccccccc', 'dddddddddddddddddddd'],
              },
            }),
          ],
        }),
      ],
    },
    { name: '', jobs: [] },
  ],
}

function issues(yaml: string): DocumentIssue[] {
  const parsed = parseWorkflow(yaml)
  if (parsed.document !== null) throw new Error('parsed')
  return parsed.issues
}

function documentOf(yaml: string): WorkflowDocument {
  const parsed = parseWorkflow(yaml)
  if (parsed.document === null) throw new Error(JSON.stringify(parsed.issues))
  return parsed.document
}

describe('the workflow document', () => {
  it('writes the layout of the built-in workflows', () => {
    expect(toYaml(rich)).toBe(`schema: 1
name: Dev build
description: |
  Line one
  line two
lock: project
inputs:
  notes:
    description: Notes
    default: ''
  plain: {}
  need:
    required: true
stages:
  - name: build
    jobs:
      build:
        name: Build \${{ flavor.name }} for \${{ platform }}
        matrix:
          platform: \${{ platforms }}
          flavor: [prod, dev]
        if: platform == 'android'
        capabilities: [flutter]
        steps:
          - kind: git.checkout
          - kind: command
            if: '!flavor.prod'
            gate: push
            with:
              '1': 'key: value'
              run: |-
                echo a
                echo b
              n: 1
              ratio: 0.5
              on: false
              nothing: null
              yes: 'true'
              list: ['a,b', '\${{ x }}', 3]
              maps:
                - a: 1
                  b:
                    c: d
                - [1, 2]
                - |-
                  x
                  y
                - []
              empty: {}
              odd: "\\n  indented"
              carriage: "a\\rb"
              trailing: "a\\n\\n"
              "line\\nkey": 1
              long:
                - aaaaaaaaaaaaaaaaaaaa
                - bbbbbbbbbbbbbbbbbbbb
                - cccccccccccccccccccc
                - dddddddddddddddddddd
  - name: ''
    jobs: {}
`)
  })

  it('reads back what it writes', () => {
    expect(documentOf(toYaml(rich))).toEqual(rich)
    const bare = { ...emptyDocument(), schema: null }
    expect(toYaml(bare)).toBe('stages: []\n')
    expect(documentOf(toYaml(bare))).toEqual(bare)
  })

  it('reads a built-in workflow and writes it back', () => {
    const document = documentOf(devBuild)

    expect(document.name).toBe('Dev build')
    expect(document.description).toBe(
      'Builds the dev flavors and sends them to testers: Android to Firebase App Distribution, iOS to TestFlight.',
    )
    expect(document.inputs[1]).toEqual(
      input({ name: 'testerGroups', description: 'Firebase tester group aliases.', defaultValue: [] }),
    )
    const upload = document.stages[1]!.jobs[0]!
    expect(upload.matrix).toEqual([
      { name: 'platform', values: null, reference: '${{ platforms }}' },
      { name: 'flavor', values: null, reference: '${{ flavors }}' },
    ])
    expect(upload.condition).toMatch(/^\(platform == 'android'/)
    expect(upload.steps[0]!.with).toEqual({ artifactsFrom: 'build', groupAliases: '${{ inputs.testerGroups }}' })
    expect(document.stages[0]!.jobs[0]!.steps.at(-1)!.with).toEqual({ checks: ['source', 'credentials'] })
    expect(documentOf(toYaml(document))).toEqual(document)
  })

  it('reads an input without fields', () => {
    expect(documentOf('inputs:\n  notes:\nstages: []\n').inputs).toEqual([input({ name: 'notes' })])
  })

  it('reads and writes typed inputs', () => {
    const typed: WorkflowDocument = {
      ...emptyDocument(),
      inputs: [
        input({
          name: 'track',
          type: 'choice',
          description: 'The track.',
          options: ['internal', 'beta'],
          defaultValue: 'internal',
        }),
        input({ name: 'release', type: 'release', required: true }),
      ],
    }

    expect(toYaml(typed)).toMatch(
      /^schema: 1\ninputs:\n {2}track:\n {4}type: choice\n {4}description: The track\.\n {4}options: \[internal, beta\]\n {4}default: internal\n {2}release:\n {4}type: release\n {4}required: true\n/,
    )
    expect(documentOf(toYaml(typed))).toEqual(typed)
  })

  it('reads empty containers as nothing', () => {
    expect(
      documentOf(`name:
inputs:
stages:
  - name: a
    jobs:
      j:
        matrix:
        capabilities:
        steps:
          - kind: x
            with:
`),
    ).toEqual({
      ...emptyDocument(),
      schema: null,
      stages: [{ name: 'a', jobs: [job({ id: 'j', steps: [step({ kind: 'x' })] })] }],
    })
  })

  it('follows aliases', () => {
    const document = documentOf(`stages:
  - name: a
    jobs:
      j:
        capabilities: &caps [flutter]
        steps:
          - kind: x
            with:
              caps: *caps
`)
    expect(document.stages[0]!.jobs[0]!.steps[0]!.with).toEqual({ caps: ['flutter'] })
  })
})

describe('parseWorkflow refuses what the model cannot hold', () => {
  it('YAML that does not parse', () => {
    const [issue, ...rest] = issues('stages: [a')
    expect(rest).toEqual([])
    expect(issue!.line).toBe(1)
    expect(issue!.message).toMatch(/^The document is not valid YAML/)
  })

  it('a document that is not a mapping', () => {
    expect(issues('- a')).toEqual([
      { line: 1, column: 1, message: 'A workflow is a mapping with "schema" and "stages".' },
    ])
    expect(issues('')[0]!.line).toBe(1)
  })

  it('unknown keys, wrong types and empty conditions, with lines', () => {
    expect(
      issues(`schema: one
lock: always
extra: 1
name: [x]
inputs:
  a: x
  b:
    required: maybe
    color: red
stages:
  - x
  - name: s
    jobs: []
  - name: t
    jobs:
      j: x
      k:
        matrix:
          platform: 3
          flavor: [prod, 4]
        capabilities: x
        if: !x
        steps:
          - x
          - with: {a: 1}
          - kind: y
            gate: [push]
`),
    ).toEqual([
      {
        line: 3,
        column: 1,
        message: 'Unknown key "extra" in the workflow. Allowed: description, inputs, lock, name, schema, stages.',
      },
      { line: 1, column: 9, message: '"schema" is a number.' },
      { line: 2, column: 7, message: '"lock" can only be "project".' },
      { line: 4, column: 7, message: '"name" is text.' },
      { line: 6, column: 6, message: 'An input is a mapping, or empty.' },
      {
        line: 9,
        column: 5,
        message: 'Unknown key "color" in input "b". Allowed: default, description, options, required, type.',
      },
      { line: 8, column: 15, message: '"required" is true or false.' },
      { line: 11, column: 5, message: 'A stage is a mapping with "name" and "jobs".' },
      { line: 13, column: 11, message: '"jobs" is a mapping.' },
      { line: 16, column: 10, message: 'A job is a mapping with "steps".' },
      {
        line: 19,
        column: 21,
        message: 'A matrix axis is a list of values or a placeholder such as ${{ platforms }}.',
      },
      { line: 20, column: 26, message: 'A value here is text.' },
      {
        line: 22,
        column: 13,
        message: '"if" is empty. Quote an expression that starts with "!", as in "!flavor.prod".',
      },
      { line: 21, column: 23, message: '"capabilities" is a list.' },
      { line: 24, column: 13, message: 'A step is a mapping with a "kind".' },
      { line: 25, column: 13, message: 'Add "kind" to the step.' },
      { line: 27, column: 19, message: '"gate" is text.' },
    ])
  })

  it('an input type it does not know, and options that are not text', () => {
    expect(issues('inputs:\n  a: {type: number, options: [1]}\nstages: []\n').map((issue) => issue.message)).toEqual([
      '"type" is one of string, boolean, choice, json, release.',
      '"options" is a list of strings.',
    ])
    expect(issues('inputs:\n  a: {options: x}\nstages: []\n')[0]!.message).toBe('"options" is a list of strings.')
  })

  it('a key that repeats', () => {
    expect(issues('name: a\nname: b\nstages: []\n')[0]).toMatchObject({ line: 2 })
  })
})

describe('YAML values', () => {
  it('format on one line and parse back', () => {
    for (const value of [
      'apk',
      '${{ inputs.notes }}',
      'true',
      '',
      "it's",
      '[a',
      3,
      1.5,
      true,
      null,
      ['a', 'b,c'],
      { 'en-US': '${{ inputs.notes }}' },
      'two\nlines',
    ]) {
      const text = formatYamlValue(value)
      expect(text).not.toContain('\n')
      expect(value === '' ? '' : parseYamlValue(text)).toEqual(value)
    }
    expect(formatYamlValue('${{ inputs.notes }}')).toBe('${{ inputs.notes }}')
    expect(formatYamlValue(['a', 'b,c'])).toBe("[a, 'b,c']")
    expect(formatYamlValue({ 'k,1': "it's" })).toBe("{'k,1': it's}")
  })

  it('read blank text as empty and broken YAML as text', () => {
    expect(parseYamlValue('  ')).toBe('')
    expect(parseYamlValue('[a')).toBe('[a')
    expect(parseYamlValue('{a: 1}')).toEqual({ a: 1 })
  })
})
