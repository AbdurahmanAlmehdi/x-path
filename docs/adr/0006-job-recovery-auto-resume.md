# ADR 0006: Job recovery and automatic resume

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** Follow-up to Phase 7 (refines D-18)
- **Approved by:** the owner, 2026-10-13

## Context

D-18 says an engine crash marks running jobs `interrupted` and that side-effect steps never
auto-resume. It does not say whether a job interrupted in a step without a side effect (a
build, a test run, a scan) needs a person to start it again. Waiting for a person after every
restart (an update, a reboot, a power cut on the Mac mini) would leave harmless work stalled
for no safety benefit.

## Decision

When `xpd serve` starts, it recovers every job left `running` and then treats the jobs by the
step that was running:

- **No side effect:** the job is `interrupted` and `xpd serve` resumes it automatically. The
  step runs again from its start (D-18: a re-run resumes at the first unfinished step).
- **Side effect** (a store upload, a tag, a push, a merge): the job goes to
  `waiting_for_resume` and stays there until someone resumes it explicitly (`POST /jobs/{id}/resume`). The engine prints a warning for each such job.

Recovery itself (stop the recorded process group, mark the step and job, delete the job's
secret files) is `JobRecovery` in `packages/xp_engine/lib/src/jobs/job_recovery.dart`; its
`RecoveryReport` splits the jobs into `resumable` and `waiting`. The startup wiring that
resumes the `resumable` ones and warns about the `waiting` ones is `_recoverJobs` in
`apps/xpd/lib/src/cli/serve_command.dart`.

## Consequences

- D-18 stands for side effects: nothing with a side effect is ever repeated without a person.
- A job interrupted by every restart (for example a crash loop in one step) is resumed after each
  one. A step that crashes the engine every time is a problem for the person watching the
  warnings, not something recovery detects.
- Recovery needs no new state: the split is derived from `step.sideEffect` of the interrupted
  step.
