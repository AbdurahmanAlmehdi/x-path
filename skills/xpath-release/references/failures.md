# Failures and what they mean

Every engine error has a code in its JSON envelope (`{"error": {"code", "message"}}`). The `xp`
CLI maps them to exit codes; `xp mcp` returns the message with `isError`.

## Exit codes of `xp`

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | the command ran, and the job it followed, the free-up, the download or the credential check failed |
| 64 | usage error (also a `400` from the engine) |
| 65 | the engine refused the content: an invalid workflow, a rejected credential (`422`) |
| 66 | no such project, job, run, approval, release, artifact or credential (`404`), or a file `xp` cannot read |
| 69 | the engine cannot be reached, or cannot serve (`502`, `503`: secrets locked) |
| 70 | the engine failed (`500`) |
| 73 | a conflict (`409`): an approval decided already, a project added already |
| 75 | `xp runner start` switched to another version |
| 77 | the token is rejected (`401`), or its kind may not do this (`403`) |
| 78 | not connected: `xp connect` first |

## Error codes

| Code | HTTP | What it means | What to do |
|---|---|---|---|
| `secrets_locked` | 503 | The engine's secret store cannot be opened: a locked login Keychain on macOS, or a missing, unreadable or wrong master key on Linux. The engine never prompts. | Tell the owner. On macOS the engine runs in the owner's login session and needs the login Keychain unlocked (log in to the Mac). On Linux, check `master.key` in the data directory or the systemd credential. Nothing can be built or uploaded meanwhile. |
| `credential_rejected` | 422 | The place a credential is for refused it (expired, revoked, wrong password, a missing role). Nothing was stored; the old credential stays. | The owner replaces it in the app (Credentials) with the fix the message gives. Never ask for the secret in chat. |
| `workflow_invalid` | 422 | The document has issues (each with `line`, `column`, `message`), or a dispatch cannot be planned: an unknown flavor, a value a step refuses, or a credential a step needs, such as `The flavor "dev" has no firebase_sa credential saved`. Nothing was stored. | Fix the document or the dispatch arguments; a missing credential is for the owner to add. |
| `already_decided` | 409 | Someone decided the approval first (another device, or it expired). The response carries the approval as it stands. | Read it with `get_approval`; nothing to retry. |
| `conflict` | 409 | The action does not fit the current state: a project added already, a built-in workflow edited or deleted, a workflow name in use, a project or workflow that jobs ran deleted, `releases build` on a release that is not `rejected`, `releases merge` on one that is not `live` with a pull request, a store status before the store has the build. | Read the state; do not retry blindly. |
| `upstream_error` | 502 | GitHub, git or a store could not be reached or failed. Adding a project without a GitHub token is also a `502`. | Check the GitHub token (skill `xpath-setup`); retry later for an outage. |
| `forbidden` | 403 | This token kind may not do this. An `mcp` token never approves or denies, changes a gate, marks a store status, abandons a release, frees storage, changes the GitHub token or pairs a runner. | Stop and ask the owner. |
| `unauthorized` | 401 | The token is unknown or revoked. | The owner makes a new token and runs `xp connect` again. |
| `not_found` | 404 | No such project, workflow, run, job, approval, release or artifact. | Check the id. |
| `resync_required` | 409 | An event stream cannot resume from its cursor. | The client reconnects and reloads; nothing to do by hand. |
| `upgrade_required` | 426 | A WebSocket route (`/events`, `/jobs/{id}/logs`) was called without a WebSocket upgrade. | Use `xp logs` or `get_job_log_tail`, not a plain HTTP request. |

`xp connect` refuses an engine of another API version ("Install the xp that matches the
engine.").

## A job that failed at a guard

A `guard` step runs checks and fails if any fails, naming each problem and its fix. Read the step
result with `get_job`.

| Check | Fails when |
|---|---|
| `source` | the worktree is not clean on the dispatched commit, or has a `pubspec_overrides.yaml` or a local path dependency |
| `credentials` | a credential the job needs was `rejected` at its last check (an `unreachable` or never-checked one only warns) |
| `versionSync` | the pubspec and the plists disagree on the version |
| `newReleaseNumber` | the version is not higher than every release before it |
| `buildNumberReuse` | a store has the build number already |
| `appStoreTrain` | the App Store version train is closed (ITMS-90186): bump the version |
| `playTargetSdk` | `targetSdk` is below what Google Play asks for (36 by default, `XPD_PLAY_TARGET_SDK` on the engine) |
| `patchTarget` | the release a patch targets does not exist |
| `patchNativeDiff` | Shorebird reports native changes in a patch (input `allowNativeDiffs` only for differences checked by hand) |

A guard failure needs a change in the repository or in the credentials; re-running does not help.

## Waiting, not failing

- **`Waiting for run <id> to finish: ...`** on a queued job: another production run of the project
  holds the project lock. It takes its turn in dispatch order.
- **`No runner can do ios-sign.`** (or `android`, `flutter`, `swift-linux`): no connected machine
  has the capability. A Mac with Xcode (for `ios-sign`) or a machine with the Android SDK must be
  the engine or a paired runner.
- **`waiting_for_approval`**: a gate. Report it to the owner; never approve.
- **`waiting_for_resume`**: a step with a side effect (an upload, a tag) was interrupted (an engine
  restart, a runner that lost its lease after 90 seconds). The engine never repeats it on its own.
  `xp jobs resume <job>` asks the step whether its work exists first.

## Store and build failures in the log

- **Google Play review in progress**: "Play has a review in progress; the release was not
  committed and the review was not cancelled". XPath never cancels a review; wait for it to end.
- **altool**: `ITMS-90186` or `ITMS-90062` (bump the version), `ITMS-90189` (the build number was
  used: dispatch again for a new one), authentication errors (the App Store Connect key or the
  app-specific password; the owner replaces the credential).
- **Firebase**: the version in the binary is not the job's version; the step names the release it
  made.
- **`build.ios` needs macOS (ios-sign)**: the job landed where there is no Xcode.
- **`test` on a branch with no baseline** fails on every failure and says to run the base branch
  first.
- **A runner's checkout**: "add this runner's SSH key as a deploy key on `<owner/repo>`", "run
  `ssh -T git@github.com` once", or a commit that was never pushed ("push it").
