import { emptyJob, emptyStep, type WorkflowDocument, type WorkflowJob, type WorkflowMatrixAxis, type WorkflowStage, type WorkflowStep } from './document'

/**
 * The edits of the visual builder, as the Mac app's `WorkflowEdits`. Each
 * returns a new document; the one it is given is left as it was.
 */

/**
 * What the inspector shows: the workflow itself ([stage] absent), a stage
 * ([job] absent) or a job of a stage.
 */
export interface WorkflowSelection {
  stage?: number
  job?: number
}

/** [selection], or the nearest one that [document] still has. */
export function within(selection: WorkflowSelection, document: WorkflowDocument): WorkflowSelection {
  const { stage, job } = selection
  if (stage === undefined || document.stages.length === 0) return {}
  const s = clamp(stage, document.stages.length - 1)
  const jobs = document.stages[s]!.jobs
  if (job === undefined || jobs.length === 0) return { stage: s }
  return { stage: s, job: clamp(job, jobs.length - 1) }
}

function clamp(value: number, max: number): number {
  return Math.min(Math.max(value, 0), max)
}

/** Adds a stage called [name] with one empty job at the end. */
export function addStage(document: WorkflowDocument, name: string): WorkflowDocument {
  return { ...document, stages: [...document.stages, { name, jobs: [emptyJob(uniqueJobId(document, name))] }] }
}

/** Replaces stage [index] with what [edit] makes of it. */
export function editStage(
  document: WorkflowDocument,
  index: number,
  edit: (stage: WorkflowStage) => WorkflowStage,
): WorkflowDocument {
  return { ...document, stages: replaced(document.stages, index, edit(document.stages[index]!)) }
}

export function removeStage(document: WorkflowDocument, index: number): WorkflowDocument {
  return { ...document, stages: removed(document.stages, index) }
}

/** Moves stage [index] by [delta] places (`-1` earlier, `1` later). */
export function moveStage(document: WorkflowDocument, index: number, delta: number): WorkflowDocument {
  return { ...document, stages: moved(document.stages, index, delta) }
}

/** Adds an empty job to stage [stage], with an id no other job has. */
export function addJob(document: WorkflowDocument, stage: number): WorkflowDocument {
  const id = uniqueJobId(document, document.stages[stage]!.name)
  return editStage(document, stage, (s) => ({ ...s, jobs: [...s.jobs, emptyJob(id)] }))
}

/** Replaces job [job] of stage [stage] with what [edit] makes of it. */
export function editJob(
  document: WorkflowDocument,
  stage: number,
  job: number,
  edit: (job: WorkflowJob) => WorkflowJob,
): WorkflowDocument {
  return editStage(document, stage, (s) => ({ ...s, jobs: replaced(s.jobs, job, edit(s.jobs[job]!)) }))
}

export function removeJob(document: WorkflowDocument, stage: number, job: number): WorkflowDocument {
  return editStage(document, stage, (s) => ({ ...s, jobs: removed(s.jobs, job) }))
}

export function moveJob(document: WorkflowDocument, stage: number, job: number, delta: number): WorkflowDocument {
  return editStage(document, stage, (s) => ({ ...s, jobs: moved(s.jobs, job, delta) }))
}

/** [base], or `base-2`, `base-3`… whichever no job of the workflow uses. */
export function uniqueJobId(document: WorkflowDocument, base: string): string {
  const used = new Set(document.stages.flatMap((stage) => stage.jobs.map((job) => job.id)))
  const stem = base === '' ? 'job' : base
  if (!used.has(stem)) return stem
  let n = 2
  while (used.has(`${stem}-${n}`)) n++
  return `${stem}-${n}`
}

/** What a new stage is called: `stage-<its number>`, as in the Mac app. */
export function newStageName(document: WorkflowDocument): string {
  return `stage-${document.stages.length + 1}`
}

export function addStep(job: WorkflowJob, kind: string): WorkflowJob {
  return { ...job, steps: [...job.steps, emptyStep(kind)] }
}

export function editStep(job: WorkflowJob, index: number, edit: (step: WorkflowStep) => WorkflowStep): WorkflowJob {
  return { ...job, steps: replaced(job.steps, index, edit(job.steps[index]!)) }
}

export function removeStep(job: WorkflowJob, index: number): WorkflowJob {
  return { ...job, steps: removed(job.steps, index) }
}

export function moveStep(job: WorkflowJob, index: number, delta: number): WorkflowJob {
  return { ...job, steps: moved(job.steps, index, delta) }
}

/** The job with the matrix axis [name] set to [axis], or without it when `null`. A new axis goes last. */
export function withAxis(job: WorkflowJob, name: string, axis: WorkflowMatrixAxis | null): WorkflowJob {
  const index = job.matrix.findIndex((each) => each.name === name)
  if (axis === null) return index < 0 ? job : { ...job, matrix: removed(job.matrix, index) }
  return { ...job, matrix: index < 0 ? [...job.matrix, axis] : replaced(job.matrix, index, axis) }
}

/**
 * [values] with [key] set to [value] in its place (at the end if new), or
 * without [key] when [value] is `undefined`.
 */
export function withValue(values: Record<string, unknown>, key: string, value: unknown): Record<string, unknown> {
  const next: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(values)) {
    if (k !== key) next[k] = v
    else if (value !== undefined) next[k] = value
  }
  if (value !== undefined && !(key in values)) next[key] = value
  return next
}

function replaced<T>(list: T[], index: number, value: T): T[] {
  return list.map((item, i) => (i === index ? value : item))
}

function removed<T>(list: T[], index: number): T[] {
  return list.filter((_, i) => i !== index)
}

function moved<T>(list: T[], index: number, delta: number): T[] {
  const to = index + delta
  if (to < 0 || to >= list.length) return list
  const copy = [...list]
  copy.splice(to, 0, ...copy.splice(index, 1))
  return copy
}
