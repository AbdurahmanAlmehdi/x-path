# ADR 0012: The Shorebird key is delivered per job like signing material

- **Status:** Accepted
- **Date:** 2026-10-14
- **Phase:** Follow-up to Phase 14a, decides Phase 14b (extends D-09)
- **Approved by:** the owner, 2026-10-14

## Context

D-09 lets signing material reach a runner for one job. Phase 14a kept `shorebird.release` and
`shorebird.patch` on the engine, because the Shorebird `sb_api_*` key is not signing material
(D-07, D-20). That kept every Shorebird flavor of a production release from building on a
runner, although the build is the expensive part.

## Decision

The Shorebird key may be delivered to a leased runner for one job only, through the mechanism
signing material uses:

- **Pull, one delivery per key per lease.** The runner asks with `secret_request` over the
  authenticated socket; the offer lists the keys only. The engine answers `secret_value` once per
  lease and key, and `secret_denied` otherwise.
- **Granted by the steps.** The key is granted when a step of the job names it (`tokenSecret` of
  `shorebird.release` and `shorebird.patch`, or `secretFiles` / `secretEnvironment`) and it is the
  key of a Shorebird credential of the project. `RunnerSecretGrants` (formerly
  `SigningSecretGrants`) grants the project's keystore and passwords, and the project's Shorebird
  keys, and nothing else. The GitHub token and store credentials stay on the engine.
- **Masked.** The engine adds the delivered text to its log masker; the runner adds it to its own.
- **Recorded.** Each delivery is a `runner.secret_delivered` event (the key, never the value).
- **Stored in the per-job secret folder** (a tmpfs folder on Linux, a 0700 folder on macOS), and
  wiped when the job ends, however it ends, and when the runner starts.

`shorebird.release` and `shorebird.patch` leave `RemoteStepPolicy`'s engine-only list. `upload.*`,
`git.push`, `git.tag`, `git.releaseBranch`, `github.*`, `gate` and `guard` stay engine-only.

## Consequences

- A Shorebird flavor of `prod-release` and `shorebird-patch` builds on a runner (ADR 0010). The
  runner needs the Shorebird CLI, which the toolchain finds like any other tool.
- A runner that is compromised during a job has that job's Shorebird key. It never has the keys of
  other jobs, and a job that names no Shorebird key gets none.
- A patch on a runner finds the Flutter version of the release in Shorebird's own release data: the
  record `shorebird.release` keeps lives in the engine's database, which a runner does not read.
