# ADR 0016: A dart-define file is a credential, delivered per job

- **Status:** Accepted
- **Date:** 2026-10-30
- **Phase:** Follow-up to ADR 0012 and ADR 0013 (extends D-09)
- **Approved by:** the owner, 2026-10-30 (Phase A of setting XPath up on real apps)

## Context

Some apps keep the values of `--dart-define-from-file` in a file outside git, so a workflow has no
file to name, and a build without those values ships an app whose requests all fail. D-09 lets only
signing material reach a runner, and ADR 0012 and ADR 0014 extended that one credential at a time.

## Decision

`dart_defines` is a named credential kind: one file per flavor, kept whole in the secret store.

- **A file the workflow names wins.** Without one, the planner gives the build and Shorebird steps,
  `record.manifest` and `build.verifyCompiledConfig` the secret key as `dartDefineSecret`. Steps
  that do not read the file do not get it.
- **It may reach a runner for one job,** through the mechanism of ADR 0012: pull, one delivery per
  key per lease, granted only when a step names it and it is a `dart_defines` credential of the
  project (`RunnerSecretGrants`). It is written with mode 0600 to the job's secret folder and wiped
  when the job ends and when the runner starts.
- **Its values are masked one by one,** with each `KEY=value` in base64, the way Flutter encodes
  them. The masker ignores values shorter than 6 characters, and hides longer ones everywhere,
  ordinary words included.
- **Results and messages name keys, never values.** The manifest records only the SHA-256.
- **No XPath process takes the values as arguments.** `flutter/build.sh` of omarchy-apple-dev reads
  defines only from its arguments, so the Linux backend sources it from a small `bash -c` that reads
  them from the 0600 file.

## Consequences

- Flutter itself passes defines to Gradle and `flutter assemble` as base64 arguments, and
  `flutter/build.sh` does the same. While Flutter compiles they are readable in the process list by
  anyone who can list processes on that machine. XPath cannot change this. A value that must never
  be on a build machine does not belong in an app's defines at all, since it ends up in the binary.
- A value that is an ordinary word, such as `release`, is hidden in all job output, which could also
  confuse a step that parses that output. Such settings do not belong in this file.
