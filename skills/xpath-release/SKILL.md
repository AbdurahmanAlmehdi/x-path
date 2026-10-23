---
name: xpath-release
description: Operate XPath, the self-hosted Flutter release tool, as an agent through the `xp` CLI or the `xp mcp` server. Use when asked to connect to an XPath engine, list projects or workflows, dispatch a dev build, a production release or a Shorebird patch (flavors, platforms, ref, bump, inputs such as firebaseAppIds or appleAppIds), follow job logs, read run, job, release or store review state, resume or cancel jobs, or when a run waits for approval. An agent never approves a gate; it stops and asks the owner.
license: Apache-2.0
---

# Releasing with XPath

XPath is a headless engine (`xpd`) that builds, signs, uploads, tags and tracks releases of Flutter
apps. You reach it through the `xp` command line or the `xp mcp` MCP server. Both talk to the
engine over HTTP; neither builds anything itself.

## The one hard rule: never approve

Gated actions wait for the owner (D-13): `prod_release`, `prod_patch`, `store_submission`, `push`,
`merge` and `delete`. An agent never decides them.

- `xp mcp` has no tool to approve, deny, merge, abandon, delete or change a gate, and the engine
  answers `403` to an `mcp` token that tries anyway.
- If you also have a shell with `xp` and a `cli` token, that token *could* approve. Do not run
  `xp approvals approve`, `xp approvals deny`, `xp releases status`, `xp releases abandon`,
  `xp storage free --apply` or `xp storage retention --keep/--log-days`. Those are the owner's
  decisions.
- When a run waits, stop and report the approval to the owner (see "When a run waits" below).
  Then poll until its state is not `pending`. `expired` (24 hours, nobody decided) counts as
  denied.

Prefer `xp mcp` for agent work: its token cannot approve, so a mistake cannot become a release.

## Connect

The owner creates tokens on the engine machine. Each is printed once; let the owner run these in
their own terminal and never ask them to paste a token into the chat.

```sh
xpd token create --name "My Mac" --kind cli      # for the xp CLI
xpd token create --name "Claude" --kind mcp      # for xp mcp
xp connect http://127.0.0.1:7480 --token <cli token> --mcp-token <mcp token>
```

With the macOS app the engine binary is
`/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd`. `xp connect` checks `GET /health`,
`GET /version` and each token before it saves anything. The URL goes to `xp.json` (in
`$XP_CONFIG_DIR`, else `$XDG_CONFIG_HOME/xpath`, else `~/.config/xpath`); the tokens go to the OS
secret store, never to that file.

Environment overrides, for scripts and CI, so nothing is saved:

| Variable | Overrides |
|---|---|
| `XP_ENGINE_URL` | the saved engine URL |
| `XP_TOKEN` | the `cli` token |
| `XP_MCP_TOKEN` | the `mcp` token (used by `xp mcp`) |
| `XP_CONFIG_DIR` | where `xp.json` lives |
| `XP_NO_UPDATE_CHECK=1` | turns off the daily release check |

Register the MCP server with Claude Code:

```sh
claude mcp add xpath -- xp mcp
```

`xp mcp` speaks MCP over stdio and uses only the `mcp` token. Its tools are listed with their
arguments in [references/mcp-tools.md](references/mcp-tools.md).

## Find the project and workflow

A project is named by its id (`prj_...`), `owner/name` or just `name`; a workflow by its id
(`wf_...`) or its name.

```sh
xp projects list
xp projects show acme/app
xp workflows list acme/app
xp workflows show acme/app dev-build
```

MCP: `list_projects`, `get_project`, `list_workflows`, `get_workflow`. Every CLI command takes
`--json`, before or after the command (`xp runs show run_... --json`), to print what the API
answered; an error is then `{"code", "message", "hint"}` on standard error.

Every project has the built-ins `dev-build`, `prod-release`, `release-merge`, `shorebird-patch`
and `test`. Read a workflow's `inputs` before dispatching it.

## Dispatch

```sh
xp dispatch <project> <workflow> [--ref <ref>] [--app <path>] [--flavor <f>]... \
  [--platform android|ios]... [--bump major|minor|patch|keep | --version x.y.z] \
  [--release-version x.y.z+build] [--input key=value]...
```

- `--ref`: branch, tag or commit; the base branch by default.
- `--app`: the app by path (`.` for the root), for monorepos.
- `--flavor`, `--platform`: repeatable. The default platforms are what the app has; the default
  flavors are the production flavors for a workflow with `lock: project` (prod-release,
  shorebird-patch) and the others otherwise.
- `--input key=value`: repeatable; the value is JSON if it parses as JSON, else text.

MCP `dispatch_workflow` takes the same as `project`, `workflow`, `ref`, `app`, `flavors`,
`platforms`, `bump`, `version`, `releaseVersion` and `inputs` (an object).

### Dev build

Android goes to Firebase App Distribution when `firebaseAppIds` or the flavor's profile names its
Firebase app; iOS goes to TestFlight when `appleAppIds` or the profile names the App Store
Connect app. Without either, `dev-build` builds and keeps the artifacts. The owner sets the
profile's ids once, in the app (Credentials, the flavor's store ids) or with
`xp projects set acme/app --flavor dev --firebase-app-id android=1:... --apple-app-id 1234567890`;
an input still wins over them.

```sh
xp dispatch acme/app dev-build --flavor dev --platform android \
  --input 'firebaseAppIds={"dev": {"android": "1:123456789012:android:abcdef"}}' \
  --input 'testerGroups=["qa"]' --input 'notes=Fixes the login crash'

xp dispatch acme/app dev-build --flavor dev --platform ios \
  --input 'appleAppIds={"dev": "1234567890"}'
```

Other `dev-build` inputs: `exportOptionsPlist` (default `ios/ExportOptions.plist`) and
`dartDefineFile` (the `--dart-define-from-file` file, relative to the app). If the owner wants
the ids every time, they belong as input defaults in a copy of the workflow (skill
`xpath-workflows`).

### Production release

```sh
xp dispatch acme/app prod-release --flavor prod --platform android --platform ios --bump patch \
  --input 'appleAppIds={"prod": "1234567890"}' --input 'playTrack=internal'
```

`prod-release` locks the project: a second release or patch of the project queues behind it.
Its inputs: `firebaseAppIds`, `testerGroups`, `notes`, `appleAppIds`, `playTrack` (default
`internal`), `exportOptionsPlist`, `dartDefineFile`. Android goes to Google Play when the flavor
has a `play_sa` credential. The run stops twice for the owner: `prod_release` before the release
branch is cut, and `push` before the branch leaves the machine (that approval also covers the
tag push at the end).

### Shorebird patch

```sh
xp dispatch acme/app shorebird-patch --flavor prod --platform android \
  --release-version 5.4.1+3283
```

`releaseVersion` is the exact `x.y.z+build` of the release it patches, never `latest`. It stops at
`prod_patch` (after the other checks passed) and at `push` for the patch tag.

### Tests

```sh
xp dispatch acme/app test --input 'paths=["test/unit"]' --input 'tags=["fast"]'
```

## Follow a run

```sh
xp runs show <run>           # jobs, states, and the approval a waiting run needs
xp jobs show <job>           # steps with their state and attempts
xp logs -f <job>             # follow until the job ends; exit 1 if it failed or was cancelled
xp logs <job> --after 120    # the lines after seq 120, then stop when the engine is quiet
xp artifacts list <job>
xp artifacts download <artifact> -o build.apk   # checks the SHA-256 the engine sends
```

MCP: `get_run`, `get_job`, `get_job_log_tail` (`lines`, 100 by default), `list_artifacts`,
`get_job_tests`. Logs are masked: secrets read `***`.

Run states: `queued`, `running`, `waiting_for_approval`, `succeeded`, `failed`, `cancelled`.
Job states add `interrupted` and `waiting_for_resume`. A failed job holds the later stages back
(`queued`, with the reason in the job's `message`) until it is resumed and succeeds.

## When a run waits

`get_run` (or `xp runs show`) shows the run as `waiting_for_approval` with `pendingApprovals`.
Stop and tell the owner, in one message:

- the approval id (`apr_...`) and its action (`prod_release`, `push`, ...);
- the project, the commit (`sha`) and the version (`x.y.z+build`) it is bound to, and the run;
- what it covers: `prod_release` cuts the release branch and lets the build and uploads go on;
  `push` pushes the release branch and, at the end, the tag; `prod_patch` publishes the OTA
  patch; `merge` merges the release pull request with a merge commit;
- when it expires (`expiresAt`, 24 hours after it was asked);
- how to approve: the XPath app (Approvals, or the needs-you bar) or
  `xp approvals approve <id>` on the owner's own machine.

Then poll `get_approval` (or `xp approvals show <id>`) until the state is `approved`, `denied` or
`expired`, and follow the run again. Do not approve, and do not look for another way around the
gate.

## Releases and the store lanes

A `prod-release` run creates one release per flavor:

```text
draft -> building -> uploaded -> in_review -> approved -> live -> merged
                                    +-> rejected -> building (a new build of the same version)
                       any state that is not over -> abandoned
```

```sh
xp releases list [--project <p>] [--app <path>] [--state <state>]
xp releases show <release>      # state, version, build, branch, tag, PR, stores, mergeEnabled
xp releases refresh <release>   # ask the stores now, past the ten-minute cache
xp releases notes <release> [--format slack|whatsapp]
```

MCP: `list_releases`, `get_release`, `get_release_notes`. Each release has a status per store
(`apple`, `play`): `pending`, `uploaded`, `in_review`, `rejected`, `approved`, `live`, with its
`source` (`upload`, `api`, `lookup`, `manual`) and a `note` when the store could not be read.
These are the App Store and Google Play lanes of the app. The release is as far as its slowest
store, and `rejected` if any store rejected it.

What only the owner does, and you only suggest:

- Mark a store approved or live by hand (`xp releases status`) when XPath cannot read that store
  (no App Store Connect key or Play service account for the flavor).
- After a rejection, a new build of the same version (`xp releases build <release>`): dispatch
  only when the owner asks for it.
- Once every store is `live`, request the merge (`xp releases merge <release>`, or Merge in the
  app). It starts `release-merge`, which waits at the `merge` gate for the owner.
- Abandon a release.

## Resume and cancel

There are no MCP tools for these; use the CLI when the owner asks.

```sh
xp jobs resume <job>                 # at the first unfinished step
xp jobs resume <job> --from-step 4   # re-run from step 4
xp jobs cancel <job>
xp runs cancel <run>                 # every job that has not ended
```

A job with a side effect (an upload, a tag) that was interrupted is `waiting_for_resume`: the
engine never repeats it on its own. On resume, the step first asks whether its work exists
(`alreadyDone`) and skips it if so. Resume a `failed`, `cancelled`, `interrupted`,
`waiting_for_resume` or `waiting_for_approval` job only after you know why it stopped.

## When something fails

Read the failing step first: `get_job` (or `xp jobs show <job>`, which prints each failed step's
message and every guard check's fix) has each step's result, and a `guard` step lists every check
with its `status`, `message` and `fix`. Then
`get_job_log_tail`. The common failures, the CLI exit codes and what each means are in
[references/failures.md](references/failures.md).

Report the message and the fix the engine gave. Do not retry a store upload, a tag or a push by
re-dispatching; resume the job so `alreadyDone` is asked first.

When a credential is the cause, `list_credentials` (with `project`) shows which named credential
each flavor uses and what its last checks found, never a secret. Agents cannot add, assign or
remove credentials: tell the owner, who uses the app or `xp credentials`.

## More

- Workflow documents, inputs and step kinds: skill `xpath-workflows`.
- Installing, tokens, credentials and runners: skill `xpath-setup`.
- The README sections "The `xp` command line", "`xp mcp`", "Workflows and the scheduler" and
  "Releases" in the XPath repository.
