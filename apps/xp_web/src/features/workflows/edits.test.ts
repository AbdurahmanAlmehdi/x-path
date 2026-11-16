import { describe, expect, it } from 'vitest'

import { emptyDocument, emptyJob, emptyStep, type WorkflowDocument } from './document'
import {
  addInput,
  addJob,
  addStage,
  addStep,
  editInput,
  editJob,
  editStep,
  inputNamePattern,
  moveJob,
  moveStage,
  moveStep,
  newStageName,
  removeInput,
  removeJob,
  removeStage,
  removeStep,
  uniqueJobId,
  withAxis,
  within,
  withValue,
} from './edits'

const document: WorkflowDocument = {
  ...emptyDocument(),
  stages: [
    { name: 'build', jobs: [emptyJob('build'), emptyJob('lint')] },
    { name: 'upload', jobs: [] },
  ],
}

describe('the selection', () => {
  it('stays where the document still has it, else goes to the nearest', () => {
    expect(within({}, document)).toEqual({})
    expect(within({ stage: 0, job: 1 }, document)).toEqual({ stage: 0, job: 1 })
    expect(within({ stage: 0, job: 5 }, document)).toEqual({ stage: 0, job: 1 })
    expect(within({ stage: 9 }, document)).toEqual({ stage: 1 })
    expect(within({ stage: 1, job: 0 }, document)).toEqual({ stage: 1 })
    expect(within({ stage: 0 }, { ...document, stages: [] })).toEqual({})
  })
})

describe('the edits of stages and jobs', () => {
  it('adds a stage with one job whose id no other job has', () => {
    const added = addStage(document, 'build')
    expect(added.stages[2]).toEqual({ name: 'build', jobs: [emptyJob('build-2')] })
    expect(document.stages).toHaveLength(2)
    expect(newStageName(document)).toBe('stage-3')
  })

  it('adds, edits, moves and removes jobs', () => {
    const added = addJob(document, 1)
    expect(added.stages[1]!.jobs).toEqual([emptyJob('upload')])
    expect(editJob(document, 0, 1, (job) => ({ ...job, name: 'Lint' })).stages[0]!.jobs[1]!.name).toBe('Lint')
    expect(moveJob(document, 0, 1, -1).stages[0]!.jobs.map((job) => job.id)).toEqual(['lint', 'build'])
    expect(moveJob(document, 0, 1, 1)).toEqual(document)
    expect(removeJob(document, 0, 0).stages[0]!.jobs.map((job) => job.id)).toEqual(['lint'])
  })

  it('moves and removes stages', () => {
    expect(moveStage(document, 1, -1).stages.map((stage) => stage.name)).toEqual(['upload', 'build'])
    expect(moveStage(document, 0, -1)).toEqual(document)
    expect(removeStage(document, 0).stages.map((stage) => stage.name)).toEqual(['upload'])
  })

  it('numbers job ids that are taken, and names a job of an unnamed stage "job"', () => {
    const taken = { ...document, stages: [{ name: '', jobs: [emptyJob('job'), emptyJob('job-2')] }] }
    expect(uniqueJobId(taken, '')).toBe('job-3')
    expect(uniqueJobId(document, 'test')).toBe('test')
  })
})

describe('the edits of steps', () => {
  const job = { ...emptyJob('build'), steps: [emptyStep('git.checkout'), emptyStep('test')] }

  it('adds, edits, moves and removes steps', () => {
    expect(addStep(job, 'command').steps.map((step) => step.kind)).toEqual(['git.checkout', 'test', 'command'])
    expect(editStep(job, 1, (step) => ({ ...step, gate: 'push' })).steps[1]!.gate).toBe('push')
    expect(moveStep(job, 1, -1).steps.map((step) => step.kind)).toEqual(['test', 'git.checkout'])
    expect(removeStep(job, 0).steps.map((step) => step.kind)).toEqual(['test'])
  })

  it('sets, replaces and drops a matrix axis', () => {
    const platform = { name: 'platform', values: null, reference: '${{ platforms }}' }
    const listed = { name: 'platform', values: ['ios'], reference: null }
    const flavor = { name: 'flavor', values: ['prod'], reference: null }
    const one = withAxis(job, 'platform', platform)
    expect(one.matrix).toEqual([platform])
    expect(withAxis(withAxis(one, 'flavor', flavor), 'platform', listed).matrix).toEqual([listed, flavor])
    expect(withAxis(one, 'platform', null).matrix).toEqual([])
    expect(withAxis(job, 'flavor', null)).toBe(job)
  })

  it('sets a value of with in its place, adds a new one last and drops one', () => {
    const values = { a: 1, b: 2 }
    expect(Object.entries(withValue(values, 'a', 3))).toEqual([
      ['a', 3],
      ['b', 2],
    ])
    expect(withValue(values, 'c', 4)).toEqual({ a: 1, b: 2, c: 4 })
    expect(withValue(values, 'a', undefined)).toEqual({ b: 2 })
    expect(withValue(values, 'c', undefined)).toEqual(values)
  })
})

describe('the inputs', () => {
  it('are added under a free name, edited and removed, the document left as it was', () => {
    const one = addInput(emptyDocument())
    const two = addInput(one)
    expect(two.inputs.map((input) => input.name)).toEqual(['input', 'input2'])
    expect(two.inputs[0]).toEqual({
      name: 'input',
      type: null,
      description: null,
      options: null,
      defaultValue: null,
      required: false,
    })
    expect(addInput(two).inputs[2]!.name).toBe('input3')

    const edited = editInput(two, 1, (input) => ({ ...input, name: 'track', type: 'choice', options: ['beta'] }))
    expect(edited.inputs[1]).toMatchObject({ name: 'track', type: 'choice', options: ['beta'] })
    expect(two.inputs[1]!.name).toBe('input2')

    expect(removeInput(edited, 0).inputs.map((input) => input.name)).toEqual(['track'])
  })

  it('are named as the engine takes them', () => {
    expect(inputNamePattern.test('track_2')).toBe(true)
    expect(inputNamePattern.test('_x')).toBe(true)
    expect(inputNamePattern.test('2track')).toBe(false)
    expect(inputNamePattern.test('a-b')).toBe(false)
  })
})
