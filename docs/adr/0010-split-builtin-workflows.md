# ADR 0010: Split the built-in workflows so builds can run on runners

- **Status:** Accepted
- **Date:** 2026-10-14
- **Phase:** Follow-up to Phases 11 and 12b, decides Phase 14b
- **Approved by:** the owner, 2026-10-14

## Context

A job is leased to a remote runner as a whole, so a job that has one engine-only step
(`RemoteStepPolicy`: `upload.*`, `git.push`, `git.tag`, `git.releaseBranch`, `github.*`, `gate`,
`guard`) runs on the engine (D-09, D-13). The built-in `dev-build`, `prod-release` and
`shorebird-patch` put a `guard` or an upload in the same job as the build, so no build could ever
go to a runner.

## Decision

The built-in workflows are split into stages, so that **the job that builds has no engine-only
step**, and everything the engine alone may do runs in an engine job of an earlier or later
stage. The runner uploads what it builds to the engine's artifact store
(`PUT /runners/jobs/{id}/artifacts/{name}`); the engine's jobs take it from there.

- **`dev-build`:** `check` (engine: `git.checkout`, `guard` source and credentials), `build`
  (runner-eligible: `git.checkout`, `version.bump`, `build.*`, `record.manifest`), `upload`
  (engine: `upload.firebase`, `upload.appStore`). The `upload` job exists only for a platform and
  flavor that has something to upload. A dev build pushes nothing, so its version commit is
  thrown away with the worktree: `version.bump` stays in the build job and runs on the runner.
- **`prod-release`:** `prepare` (engine, as before, and then `git.push` of the release branch),
  `check` (engine: the guards that were in the build job), `build` (runner-eligible:
  `git.checkout` from the version commit, `shorebird.release` or `build.*`, `symbols.archive`,
  `record.manifest`), `upload` (engine: `upload.play`, `upload.firebase`, `upload.appStore`) and
  `finalize` (engine: `git.tag`, `git.push` of the tag, `github.createPr`).
- **`shorebird-patch`:** `check` (engine: the guards and the `prod_patch` gate), `patch`
  (runner-eligible: `git.checkout`, `shorebird.patch`), `finalize` (engine: tag and push).

Three details follow from the owner's decisions:

- **The release branch is pushed before the build.** A runner fetches the exact commit from
  GitHub (ADR 0009), so the version commit must be there. `prepare` pushes the branch
  (`git.push` with `tag: false`, behind the `push` gate) right after `git.releaseBranch`. The
  tag is still pushed last. An approval binds to the project, action, commit, version and run
  (D-13), so the owner's approval of that push also covers the push of the tag in `finalize`.
- **An upload takes its file from the build job.** `upload.play`, `upload.firebase` and
  `upload.appStore` take `artifactsFrom: <job>` under `with`. The planner stores the id of the job
  of the same matrix cell in the step input as `artifactJob`, and the step looks for the artifact
  there instead of in its own job. A step that names no job looks in its own, as before.
  `artifactsFrom` names a job of an earlier stage, like `commitFrom`.
- **The `prod_patch` gate sits in front of the last guard of the `check` job**, since a gate is an
  attribute of a step and the patch step itself is on the runner. The checks that can fail
  (credentials, release, native changes) run before the owner is asked.

The `test` step is engine-only as well (it judges against a baseline and stores the run, both in
the engine's database, D-21), so that a `test` job is never leased to a runner that has neither.

Built-in workflow documents get a new version when the engine ships a different document
(Phase 11): a project that has the older version keeps running its runs on it, and the next
dispatch uses the new one.

## Consequences

- A run has more jobs: a dev build of one flavor and platform is a check, a build and (with
  something to upload) an upload job, in three stages. The desktop app and the CLI show them as
  they show any run.
- A build job goes to a runner only when the engine cannot take it or has no free slot (the
  scheduler prefers the engine, 14a). That does not change.
- The release branch of a production release exists on GitHub before the stores have seen the
  build. A failed release leaves the branch behind (never the tag).
- The end-to-end scripts (`release_e2e.sh dev` and `prod`, `mcp_gate_e2e.sh`) walk the new
  stages.
