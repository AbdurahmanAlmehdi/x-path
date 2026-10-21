---
title: "feat: ease of use and UX across workflows, the app, the CLI and MCP"
type: feat
date: 2026-10-21
---

## feat: ease of use and UX across workflows, the app, the CLI and MCP

## Overview

XPath 1.0 works end to end, but the path a new owner takes from install to a first release, and
the path an existing owner takes when something fails, have more friction than the engine
warrants. The engine already records most of what the user needs (step messages, queue reasons,
guard fixes, notification kinds, phased-release state); the clients often drop it.

This plan collects every change from the 2026-10-20 UX research (four audits: workflows, the
desktop app, the CLI/MCP/docs, and a benchmark of Codemagic, Bitrise, Xcode Cloud, GitHub
Actions, EAS, Fastlane, Runway, Tramline, Appcircle and the Shorebird console) and orders them
into phases. Each phase is one PR (or one per sub-phase), fits one context window, and leaves
the workspace green.

Phases are numbered `U1`…`U8` so they do not collide with the 1.0 plan's numbering. Phase U8
absorbs the docs part of the 1.0 plan's Phase 19.

## Problem Statement

- **Releasing from the app is not possible for the built-ins.** The dispatch sheet sends only
  app, ref, flavors, platforms and bump (`apps/xp_desktop/lib/dispatch/bloc/dispatch_bloc.dart:168-174`).
  `dev-build` never uploads (its `upload` job needs `firebaseAppIds`/`appleAppIds` inputs,
  `packages/xp_engine/lib/src/workflows/builtin_workflows.dart:94-96`) and `shorebird-patch`
  always fails with "give releaseVersion" (`packages/xp_engine/lib/src/dispatch/workflow_dispatcher.dart:425-430`).
  The guide's workaround is to fork a built-in and hand-edit JSON (`docs/guide/try-it-locally.md:158-174`).
- **Failures and waits are silent.** The job hero says "Failed at <step>"; `step.message` is a
  hover tooltip (`apps/xp_desktop/lib/job/widgets/step_list.dart:95-96`); the scheduler's queue
  reasons in `job.message` are only rendered inside the interrupted banner
  (`apps/xp_desktop/lib/job/view/job_page.dart:408`). `xp jobs show` drops `step.message` and
  guard `fix`es (`apps/xp/lib/src/commands/runs_commands.dart:211-217`).
- **Work is easy to lose.** Builder edits vanish on sidebar navigation; there is no undo;
  several destructive actions have no confirmation; the GitHub-token detour in Add project
  drops the typed folder; a dispatched dev build is unreachable once you navigate away; there
  is no `GET /runs`.
- **Authoring workflows is raw.** Every `with` field is free text ("YAML value"), inputs are
  read-only in the builder, typos in variable paths validate and evaluate to `null`, required
  `with` keys fail only at dispatch, forks of built-ins never receive engine updates.
- **The app does not yet match its own design guides.** No toasts, skeletons, ⌘K, back/forward,
  menus, context menus, Reduce Motion or compact mode; many rows are mouse-only; closing the
  window quits the app and its menu bar extra (`apps/xp_desktop/macos/Runner/AppDelegate.swift:6`).
- **Setup and docs.** Getting a CLI/MCP token needs the bundled `xpd` path; there is no
  `xp status`/`doctor`; the README is a 180 KB reference with no Quickstart or Troubleshooting.

## Resolved design decisions

Proposed; to confirm with the owner before Phase U2 starts.

| # | Decision |
|---|---|
| UX-01 | The engine is the single source of truth for planning. The dispatch preview comes from an engine dry run, not from client re-implementation (`packages/xp_repositories/lib/src/workflows/dispatch_preview.dart`). |
| UX-02 | The builder only ever serializes to the same YAML document; no hidden builder state (avoid Codemagic's split between editor and `codemagic.yaml`). |
| UX-03 | Per-flavor store identifiers (Firebase app id, App Store Connect app id) live on `FlavorProfile`. Built-ins read them when the matching input is empty. Inputs still override. |
| UX-04 | Inputs get a type (`string`, `boolean`, `choice`, `json`, `release`) and an optional `options` list. Untyped inputs keep today's behaviour (`string`, JSON-coerced in the CLI). `schema: 1` stays; new keys are optional. |
| UX-05 | Every API error may carry an optional `hint` (one sentence, client-neutral) and optional `details`. Clients render the hint; CLI-only advice stays in the CLI. |
| UX-06 | Workflows that have run are archived, not deleted. Archived workflows are hidden from dispatch pickers and listed under "Archived" in the builder. |
| UX-07 | Closing the main window keeps XPath running in the menu bar (setting, on by default). Quit stays ⌘Q. |
| UX-08 | Destructive actions confirm with a dialog that names the object and the consequence; reversible actions use an undo toast instead. |
| UX-09 | Words in the app, CLI and MCP match (PRODUCT §3): one name per concept, no HTTP paths or CLI commands in engine messages shown by the app. |

## Implementation Phases

| Phase | PR | Phase | PR |
|---|---|---|---|
| U1a | Quick fixes: desktop | U4a | Runs API, CLI follow, MCP runs |
| U1b | Quick fixes: CLI, MCP and engine wording | U4b | Desktop runs, re-run and logs |
| U2a | Flavor store identifiers | U4c | Desktop feedback kit |
| U2b | Typed inputs and the dispatch form | U5 | First run and setup |
| U2c | Engine dry run and dispatch picker | U6a | Navigation, menus and the command palette |
| U3a | Deeper validation and structured issues | U6b | Menu bar, notifications and window |
| U3b | Rich step schema and typed step editor | U6c | Accessibility, density and context menus |
| U3c | Builder editing: undo, inputs, templates | U6d | Information architecture |
| U3d | Workflow lifecycle and fork tracking | U7 | Release management and rollout controls |
| U3e | Comment-preserving YAML writer (optional) | U8 | Docs, quickstart and troubleshooting |

U1a and U1b are independent and can land in any order. U2a → U2b → U2c are ordered. U3 depends on
U2b (typed inputs) for U3c's input editor. U4a precedes U4b. U6 can start after U4c (toasts are
used by the palette and context menus). U8 runs last but its Quickstart can be drafted after U2.

### Phase U1a: Quick fixes: desktop

- **Status:** Not started
- **Scope:**
  - Job page: a failure banner with the failed step's `message` and the run's `message`; for a
    queued job, show `job.message` (the scheduler's wait reason, e.g. "No runner can do
    ios-sign") under the hero (`apps/xp_desktop/lib/job/view/job_page.dart:80-83,366-380,408`).
  - Rename "Re-run all" to "Restart job" (it resumes the selected job from step 0,
    `job_page.dart:153-161`).
  - Builder: route `ShellCubit.show` through a "can leave?" hook so sidebar navigation and ⇧⌘A
    ask before discarding a dirty draft (`apps/xp_desktop/lib/shell/cubit/shell_cubit.dart:133-136`,
    `apps/xp_desktop/lib/workflow_builder/view/workflow_builder_page.dart:76-82`).
  - Builder "Save as…": pre-fill `<name>-copy`, check the name pattern and uniqueness in the
    dialog (`workflow_builder_page.dart:89-92`, `workflow_builder/widgets/workflow_dialogs.dart`).
  - Builder lock chip: say that `lock: project` also makes prod flavors the default
    (`app_en.arb:1388`; `workflow_dispatcher.dart:362-375`).
  - Confirm dialogs (UX-08, reuse `runners/widgets/revoke_runner_dialog.dart`) for: Remove
    engine (`engines/view/engines_page.dart:112`), Remove on the missing-token page plus a new
    "Try again" primary (`app/view/app.dart:200-202`), Remove GitHub token
    (`settings/widgets/github_token_section.dart:113`), Remove project in the scan review
    (`add_project/view/add_project_page.dart:207`), Mark approved / Mark live
    (`releases/widgets/store_lane.dart:268-273`), and removing a stage/job/step in the builder
    (`workflow_builder/widgets/workflow_inspector.dart:184-187,260-263`, `builder_controls.dart:441-445`).
  - Add project: show `GitHubTokenSection` inline instead of navigating to Settings, so the
    folder and scan state survive (`add_project/view/add_project_page.dart:116-135`).
  - Empty states with a call to action: Releases → "Dispatch Prod release…", Tests → "Run
    Tests…", Credentials → "Add credential…".
  - ⌘N (dispatch for the current project) handled in `AppShell`, not only Overview; ⌘1–⌘9 select
    projects.
  - Formatting: `fieldFileChosen` uses `formatSize` (`app_en.arb:398`); times older than 24 h show a
    date and every time has an absolute tooltip (`project_overview/widgets/release_rail.dart:69`,
    `approvals/view/approvals_page.dart:190`); SHAs click to copy.
  - Banners: "Show log in Finder" on `localEngineTimedOut`; unlock steps on
    `bannerSecretsLocked`; for a rejected *local* engine, offer "Set up this Mac again"
    (`shell/widgets/connection_banner.dart`).
  - Approvals: disable Approve and Deny together when read-only (`approvals/view/approvals_page.dart:290-305`).
  - Store lane "Add API key" opens that flavor's credential sheet, not the whole page
    (`releases/widgets/store_lane.dart:280`).
- **Files touched:** `apps/xp_desktop/lib/{job,workflow_builder,shell,engines,app,settings,add_project,releases,tests,credentials,approvals,project_overview,widgets}/**`, `apps/xp_desktop/lib/l10n/arb/app_en.arb`, `apps/xp_desktop/test/**`
- **Acceptance criteria:**
  - A failed job shows the failed step's message without hovering; a queued job shows why.
  - Clicking another sidebar row with a dirty builder asks first; Cancel keeps the draft.
  - "Save as…" on a built-in succeeds on the first press with the default name.
  - Every listed destructive action asks first; Cancel changes nothing.
  - Connecting GitHub from Add project keeps the chosen folder.
  - ⌘N opens the dispatch sheet from Releases, Tests and the Job view.
- **Validation:** `melos run analyze && melos run format && melos run test:coverage`

### Phase U1b: Quick fixes: CLI, MCP and engine wording

- **Status:** Not started
- **Scope:**
  - `xp jobs show`: print each failed step's `message` and every guard check's `fix`; print step
    states with `.wire` like jobs (`apps/xp/lib/src/commands/runs_commands.dart:211-217`).
  - `--json` accepted on every subcommand, not only the root; with `--json`, errors go to stderr
    as `{"code","message","hint"}` (`apps/xp/lib/src/command_runner.dart:51-55`,
    `apps/xp/lib/src/commands/xp_command.dart:104-123`).
  - No Dart stack trace on usage/parse errors (`command_runner.dart:92-97`).
  - `xp projects add`: a path-like argument that does not exist is a usage error, not a GitHub
    remote (`projects_commands.dart:137-140`).
  - `xp logs` without `-f`: wait until the job's log reports its end instead of 750 ms of silence
    (`apps/xp/lib/src/context.dart:28`).
  - Engine messages without client jargon (UX-09): replace "mark one with PATCH /projects/{id}"
    (`workflow_dispatcher.dart:370-371`) and "(xp credentials assign)" (`step_planners.dart:564-569`)
    with plain wording; the CLI adds its own command hint.
  - MCP: `ReferenceException` hints name MCP tools in MCP (`list_projects`), CLI commands in the
    CLI (`apps/xp/lib/src/resolve.dart:291,314,348`, `apps/xp/lib/src/mcp/xp_tools.dart:587-588`);
    the catch-all no longer says "Invalid arguments" for non-argument errors (`xp_tools.dart:591-592`);
    tool results carry the `ApiErrorCode`.
  - D-13 wording: the plan and skills say `xp approvals approve` (not `xp approve`).
- **Files touched:** `apps/xp/lib/**`, `apps/xp/test/**`, `packages/xp_engine/lib/src/dispatch/**`, `packages/xp_engine/test/**`, `skills/xpath-release/**`, `docs/plan/2026-10-13-feat-xpath-release-tool-plan.md`
- **Acceptance criteria:**
  - `xp jobs show <failed job>` prints the step message and guard fixes.
  - `xp projects list --json` works; `xp --json runs show bad_id` prints a JSON error.
  - `xp projects add ./typo` exits 64 with "No folder at ./typo".
  - No engine error string contains `PATCH /` or `xp `.
- **Validation:** `melos run analyze && melos run test:coverage && ! grep -rnE "PATCH /|\\(xp [a-z]" packages/xp_engine/lib`

### Phase U2a: Flavor store identifiers

- **Status:** Not started
- **Scope:** Add `firebaseAppId` (per platform) and `appleAppId` to `FlavorProfile`
  (`packages/xp_api/lib/src/project_profile.dart`), a migration, `ProfileEdits` support, and
  expression variables `flavor.firebaseAppId` / `flavor.appleAppId`. Scan pre-fills them where
  `firebase_options.dart` / `GoogleService-Info.plist` / `google-services.json` name them. Built-ins
  fall back to them when `firebaseAppIds` / `appleAppIds` inputs are empty (UX-03), and the
  built-in version is bumped so existing engines pick up the change. Desktop: the per-flavor row
  in Credentials (and Project settings once U6d lands) edits them; scan findings for a missing id
  link to the field. CLI: `xp projects set <project> --flavor dev --firebase-app-id android=…`.
- **Files touched:** `packages/xp_api/lib/src/{project_profile,profile_edits}.dart`, `packages/xp_api/openapi.yaml`, `packages/xp_adapters/lib/src/sqlite/migrations.dart`, `packages/xp_adapters/lib/src/scan/**`, `packages/xp_engine/lib/src/workflows/{builtin_workflows,expression}.dart`, `apps/xpd/lib/src/api/projects/**`, `apps/xp/lib/src/commands/projects_commands.dart`, `apps/xp_desktop/lib/credentials/**`
- **Acceptance criteria:** with ids set on the `dev` flavor, dispatching built-in `dev-build`
  from the app with no inputs runs the `upload` job; an input still overrides the flavor value.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U2b: Typed inputs and the dispatch form

- **Status:** Not started
- **Scope:**
  - Inputs gain `type` and `options` (UX-04) in the parser, `InputDefinition`
    (`packages/xp_engine/lib/src/workflows/workflow_definition.dart:56-80`) and the wire
    `Workflow` type; built-ins declare types (`releaseVersion: release`, app ids `json`).
  - The dispatch sheet gets an Inputs section generated from the declared inputs: text,
    switch, dropdown, a JSON field with validation, and a release picker (from the project's
    releases) for `release` inputs. It also gets an explicit version field next to bump. The
    request sends `inputs`, `version` and `releaseVersion`
    (`apps/xp_desktop/lib/dispatch/bloc/dispatch_bloc.dart:168-174`, `dispatch/view/dispatch_sheet.dart`).
  - The sheet remembers the last inputs per workflow and project.
  - CLI: `--input-file <yaml|json>`; inputs are coerced by declared type, not "anything that
    parses as JSON" (`runs_commands.dart:95-101`); on a TTY, missing required inputs are prompted.
  - MCP `dispatch_workflow` describes the declared inputs and their types.
- **Files touched:** `packages/xp_engine/lib/src/workflows/**`, `packages/xp_api/lib/src/workflow.dart`, `packages/xp_api/openapi.yaml`, `packages/xp_repositories/lib/src/workflows/**`, `apps/xp_desktop/lib/dispatch/**`, `apps/xp/lib/src/commands/runs_commands.dart`, `apps/xp/lib/src/mcp/xp_tools.dart`
- **Acceptance criteria:** `shorebird-patch` dispatches from the app after picking a release;
  `dev-build` can upload to a one-off Firebase app id typed in the sheet; `xp dispatch … notes=true`
  on a `string` input sends the string `"true"`.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U2c: Engine dry run and dispatch picker

- **Status:** Not started
- **Scope:**
  - `POST /projects/{id}/workflows/{wf}/dispatch?dryRun=true` (UX-01) returns stages, planned
    jobs, **skipped jobs with the reason** (false `if`, no app id, missing credential, missing
    required `with` key), gates, runner capability matches and the version/build number it
    would allocate (without allocating).
  - The dispatch sheet preview uses it instead of `WorkflowOutline`; the preview never disables
    Dispatch because the client could not parse YAML the engine accepts
    (`dispatch_bloc.dart:177-181,333-337`).
  - Picker shows the workflow's `name` and `description` (add both to `WorkflowSummary`),
    defaults to the last-used workflow, hides `release-merge` and archived workflows.
  - `showDispatchSheet(context, project, workflowId:)` and a "Run…" button in the builder.
  - CLI `xp dispatch --dry-run` prints the same plan.
- **Files touched:** `packages/xp_engine/lib/src/dispatch/workflow_dispatcher.dart`, `apps/xpd/lib/src/api/workflows/workflows_routes.dart`, `packages/xp_api/**`, `packages/xp_client/lib/src/xp_client.dart`, `packages/xp_repositories/lib/src/workflows/**`, `apps/xp_desktop/lib/{dispatch,workflow_builder}/**`, `apps/xp/lib/src/commands/runs_commands.dart`
- **Acceptance criteria:** dispatching `dev-build` with no app ids shows "upload: skipped, no
  Firebase or App Store app id for dev"; the dry run allocates no build number (counter unchanged).
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U3a: Deeper validation and structured issues

- **Status:** Not started
- **Scope:**
  - Check full member paths for known scopes: `inputs.<declared>`, `flavor.<field>`,
    `platform`, `release.<field>` (`workflow_parser.dart:547-561`, `expression.dart:51`).
  - Check required `with` keys and value shapes at validate time, not only at dispatch
    (`step_planners.dart` decoders).
  - "Did you mean" (edit distance) for kinds, keys, gates and variables, instead of dumping the
    catalogue (`workflow_parser.dart:414-417`).
  - `workflow_invalid` error bodies carry `issues: [{line, column, message, hint}]` instead of one
    flattened sentence (`workflow_exceptions.dart:100-105`); the CLI prints one issue per line
    (`workflows_commands.dart:178-191`).
  - `xp workflows validate <file>` without a project (validation is project-independent).
- **Files touched:** `packages/xp_engine/lib/src/workflows/**`, `packages/xp_engine/lib/src/dispatch/step_planners.dart`, `packages/xp_api/**`, `apps/xpd/lib/src/api/workflows/**`, `apps/xp/lib/src/commands/workflows_commands.dart`
- **Acceptance criteria:** `if: inputs.firebaseAppId != null` (undeclared) is an issue with "did
  you mean `inputs.firebaseAppIds`?"; a `build.ipa` step without `exportOptionsPlist` fails
  validation with a line number.
- **Validation:** `melos run test:coverage`

### Phase U3b: Rich step schema and typed step editor

- **Status:** Not started
- **Scope:**
  - `StepType` (`packages/xp_api/lib/src/workflow.dart:247-260`) gains `title`, `description`,
    `group`, and per key `type`, `required`, `default`, `options`, `description`; gates gain a
    label. Filled from `StepPlanners`/`step_catalog.dart`.
  - Builder: kind menu grouped and searchable with descriptions; `with` fields typed (switch,
    dropdown, number, path, credential picker) with required markers; gates shown by label; `if`
    field completes variables (`workflow_inspector.dart:501-518,737-748`).
  - When the engine is unreachable, the step picker is disabled with a reason instead of
    falling back to `command`, and existing issues stay visible (`workflow_inspector.dart:492-499`,
    `workflow_builder_bloc.dart:561-567`).
  - `xp workflows schema [--kind <kind>]`; MCP `get_workflow_schema` tool and the schema served as
    an MCP resource (skill no longer tells agents to `curl`, `skills/xpath-workflows/SKILL.md:94`).
  - Publish the schema as JSON Schema at `site/schema/workflow-1.json` for editor completion.
- **Files touched:** `packages/xp_api/lib/src/workflow.dart`, `packages/xp_engine/lib/src/workflows/step_catalog.dart`, `packages/xp_engine/lib/src/dispatch/step_planners.dart`, `apps/xp_desktop/lib/workflow_builder/**`, `apps/xp/lib/src/{commands/workflows_commands,mcp/xp_tools}.dart`, `skills/xpath-workflows/**`, `site/schema/**`
- **Acceptance criteria:** every built-in step kind has a description and typed keys (a test
  fails if one does not); the builder marks a missing required key before save.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U3c: Builder editing: undo, inputs, templates

- **Status:** Not started
- **Scope:**
  - Undo/redo (⌘Z / ⇧⌘Z) as a stack of YAML snapshots in `WorkflowBuilderBloc`; removing a
    stage, job or step shows an undo toast (from U4c, or a local one until then).
  - Visual input editor: name, description, type, options, default, required (replaces "Inputs
    are edited in the YAML.", `workflow_inspector.dart:123-143`).
  - "New workflow" offers templates: blank, Android → Firebase, iOS → TestFlight, tests only,
    Shorebird patch (`workflow_builder_bloc.dart:284-297`).
- **Files touched:** `apps/xp_desktop/lib/workflow_builder/**`, `packages/xp_engine/lib/src/workflows/builtin_workflows.dart` (templates live beside built-ins), `apps/xpd/lib/src/api/workflows/**`
- **Acceptance criteria:** remove a step, press ⌘Z, the YAML equals the previous YAML; a workflow
  created from each template validates.
- **Validation:** `melos run test:coverage`

### Phase U3d: Workflow lifecycle and fork tracking

- **Status:** Not started
- **Scope:**
  - Version history drawer in the builder: list versions (`Workflow.versions`), diff any two,
    restore one as a new version.
  - Archive/unarchive (UX-06) in the API, app, CLI and MCP; hard delete only for workflows that
    never ran (wire up the existing `DELETE`, `workflows_routes.dart:27`, `xp_client.dart:193`).
  - Rename.
  - `basedOn: {builtin, version}` stored on "Save as" from a built-in; the builder shows
    "Built-in updated: compare" when a newer built-in exists, with a three-way diff view.
  - CLI: `xp workflows delete|archive|versions|diff|copy`.
- **Files touched:** `packages/xp_api/lib/src/workflow.dart`, `packages/xp_adapters/lib/src/sqlite/**`, `packages/xp_engine/lib/src/workflows/**`, `apps/xpd/lib/src/api/workflows/**`, `apps/xp_desktop/lib/workflow_builder/**`, `apps/xp/lib/src/commands/workflows_commands.dart`, `apps/xp/lib/src/mcp/xp_tools.dart`
- **Acceptance criteria:** a fork of `dev-build` shows the compare prompt after the engine ships
  a new `dev-build` version; an archived workflow is absent from the dispatch picker.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U3e: Comment-preserving YAML writer (optional)

- **Status:** Not started
- **Scope:** Visual edits apply minimal changes with `yaml_edit` instead of regenerating the
  document with `toYaml()`, so comments and layout survive (`workflow_document.dart:10-15`,
  `workflow_builder_bloc.dart:514`).
- **Files touched:** `apps/xp_desktop/lib/workflow_builder/**`, `apps/xp_desktop/pubspec.yaml`
- **Acceptance criteria:** a commented workflow, edited visually (rename a job), keeps every
  comment; the existing round-trip test still passes.
- **Validation:** `melos run test:coverage`

### Phase U4a: Runs API, CLI follow, MCP runs

- **Status:** Not started
- **Scope:**
  - `GET /runs?project=&workflow=&state=&limit=&before=` and `GET /projects/{id}/runs`.
  - `ApiError` gains optional `hint` and `details` (UX-05, `packages/xp_api/lib/src/api_error.dart:88-109`);
    `secrets_locked`, engine unreachable, `workflow_invalid`, credential and runner-capability
    errors set hints. `xp_client` turns socket errors into "Cannot reach the engine at … Is xpd
    running?" with the health URL.
  - CLI: `xp runs list`, `xp runners list`, `xp dispatch --follow` (streams every job's log with a
    job prefix, exits with the run's state), `xp logs <run_id>` for all jobs of a run, coloured
    states and spinners on a TTY, local times with the zone shown (`output/format.dart:24-31`).
  - MCP: `list_runs`, `list_runners`, `wait_for_run` (bounded), `wait_for_approval` (bounded).
- **Files touched:** `packages/xp_api/**`, `packages/xp_engine/lib/src/**` (run queries), `packages/xp_adapters/lib/src/sqlite/**`, `apps/xpd/lib/src/api/runs/**`, `packages/xp_client/**`, `apps/xp/lib/**`
- **Acceptance criteria:** after `xp dispatch` in another terminal, `xp runs list --project p`
  shows the run; `xp dispatch --follow` exits 0 on success and non-zero on failure.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U4b: Desktop runs, re-run and logs

- **Status:** Not started
- **Scope:**
  - Overview: "Recent runs" (last N runs of any workflow, with status, workflow, flavors, who
    or what triggered it) (PRODUCT §6.2); a project-level Runs list with filters.
  - "Run again" on any finished run: re-dispatches with the same request; "Re-run failed jobs"
    on a failed run resumes each failed job from its failed step, reusing artifacts already
    produced.
  - Log view: open on the failed step, highlight the error line, search within the log, link to
    a line (copy), collapse step groups.
  - Job view: artifacts list with Reveal, Copy path and Download (`job/view/job_page.dart:336`).
  - A run summary card at the top of a finished run: version, build number, store links,
    test counts.
- **Files touched:** `apps/xp_desktop/lib/{project_overview,job}/**`, `packages/xp_repositories/lib/src/**`, `packages/xp_engine/lib/src/**` (re-dispatch, re-run failed), `apps/xpd/lib/src/api/runs/**`
- **Acceptance criteria:** a dev build dispatched, then left, is reachable from Overview; "Run
  again" creates a new run with identical inputs; a failed upload re-runs without a rebuild.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U4c: Desktop feedback kit

- **Status:** Not started
- **Scope:**
  - Toast service (bottom right, 4 s / 6 s, motion tokens already defined) used for every command
    result: saved, verified, marked, merged, cancelled, freed. Replace ad-hoc inline messages.
  - `XpLoading` skeletons replace blank `SizedBox()` placeholders (`shell/view/app_shell.dart:147`,
    `job/view/job_page.dart:59,115`, approvals, storage).
  - `XpErrorState` with Retry and a human fallback instead of `'$error'`
    (`packages/xp_repositories/lib/src/errors.dart:11`, `onboarding/bloc/onboarding_bloc.dart:195`);
    renders `ApiError.hint`. Stop borrowing unrelated statuses for load errors
    (`credentials/view/credentials_page.dart:158`).
  - Staleness: a "Cached · 14:02" chip driven by the existing `cached` flags; running timers and
    spinners pause while the engine is not connected; menu bar countdowns tick.
- **Files touched:** `apps/xp_desktop/lib/widgets/**`, `apps/xp_desktop/lib/theme/**`, every feature `view/` that renders loading or errors, `packages/xp_repositories/lib/src/errors.dart`
- **Acceptance criteria:** no `XpMessage(XpStatus.scanError, …)` without a Retry remains; with
  the engine stopped, a running job's timer stops and the cached chip appears.
- **Validation:** `melos run test:coverage && ! grep -rn "'\\$error'" apps/xp_desktop/lib packages/xp_repositories/lib`

### Phase U5: First run and setup

- **Status:** Not started
- **Scope:**
  - Onboarding says up front what a first release needs (engine, GitHub, project, store
    credentials).
  - A setup checklist on NoProjects and Overview: engine ✓ → GitHub → project → credentials per
    flavor → store ids (U2a) → first dispatch, each step deep-linking to its sheet; hides once done.
  - Scan findings get actions ("Add credential…", "Set Firebase app id…", "Copy path") instead of
    text-only "Fix: …" (`projects/widgets/scan_summary.dart:254`).
  - Tokens from the app: Settings ▸ CLI and agents ▸ "New token" shows a ready-to-paste
    `xp connect …` command and an MCP config snippet (needs a token-minting route for the
    owner's desktop token).
  - `xp status` (engine, version, token name, health, secrets state), `xp doctor` (toolchain and
    credential checks), `xp disconnect`.
  - CLI defaults the project from the current folder's git remote when it matches one project.
  - A first unsigned smoke build: "Try a debug build" right after the scan, to see green before
    signing is configured.
- **Files touched:** `apps/xp_desktop/lib/{onboarding,projects,project_overview,settings}/**`, `apps/xpd/lib/src/api/**` (token route), `apps/xp/lib/src/commands/**`, `apps/xp/lib/src/config/**`, `packages/xp_engine/lib/src/workflows/builtin_workflows.dart`
- **Acceptance criteria:** a new owner reaches a first green build without leaving the app or
  reading docs; `xp status` works with no project argument; a token minted in the app connects
  `xp` without touching the `xpd` binary.
- **Validation:** `melos run test:coverage && manual 1. Remove ~/Library/Application Support/XPath on a test user. 2. Install the app. 3. Follow only on-screen guidance to a green dev build. 4. Count interactions (target: under 12).`

### Phase U6a: Navigation, menus and the command palette

- **Status:** Not started
- **Scope:**
  - History stack in `ShellCubit` with ⌘[ / ⌘] back and forward.
  - ⌘K command palette: go to project, release, run, workflow or setting; run Dispatch, Run
    again, Cancel, Approve (approve still opens the review sheet, D-13).
  - A real macOS main menu via `PlatformMenuBar` (Go, Project, Job) listing every shortcut;
    ⌘/ shortcut sheet; ⌃⌘S sidebar toggle (`docs/design/system/project/guide/08-keyboard.md`).
- **Files touched:** `apps/xp_desktop/lib/shell/**`, `apps/xp_desktop/lib/app/**`, `apps/xp_desktop/lib/widgets/**`
- **Acceptance criteria:** every shortcut in the keyboard guide works and appears in a menu;
  Job → ⌘[ returns to the page that opened it.
- **Validation:** `melos run test:coverage`

### Phase U6b: Menu bar, notifications and window

- **Status:** Not started
- **Scope:**
  - Closing the window keeps the app in the menu bar (UX-07,
    `apps/xp_desktop/macos/Runner/AppDelegate.swift:6`), with a setting.
  - Menu bar extra: running jobs with progress, needs-you, quick dispatch (PRODUCT §6.13).
  - macOS notifications for the engine's existing kinds beyond approvals: `jobFailed`,
    `jobSucceeded`, `releaseRejected`, `releaseApproved`, `releaseLive`, `credentialExpired`,
    `secretsLocked` (`packages/xp_api/lib/src/notification.dart`); clicking opens the page;
    per-kind toggles in Settings.
  - Restore window frame and last destination.
- **Files touched:** `apps/xp_desktop/macos/Runner/**`, `packages/xp_macos_services/**`, `apps/xp_desktop/lib/{approvals,settings,app}/**`
- **Acceptance criteria:** with the window closed, a failed prod job posts a notification that
  opens the job.
- **Validation:** `melos run test:coverage && manual 1. Close the window. 2. Dispatch a failing prod job from xp. 3. Click the notification; the job page opens.`

### Phase U6c: Accessibility, density and context menus

- **Status:** Not started
- **Scope:**
  - Clickable rows become focusable (`FocusableActionDetector`): sidebar, approvals, flavor
    ledger cells, pipeline nodes, step rows, `XpSegmented`, console strip; ↑/↓/↩ in lists
    (`shell/widgets/sidebar.dart:440`).
  - Semantics: labels on `XpStatusIcon` and sidebar badges; drop `excludeSemantics` that hides
    counts (`sidebar.dart:435`); remove empty tooltips (`shell/widgets/engine_switcher.dart:25`,
    `widgets/xp_select.dart:34`); keep focus on busy `XpButton`s.
  - Reduce Motion from `MediaQuery.disableAnimationsOf` and compact density (⌃⌘=) passed to
    `appTheme` (`app/view/app.dart:58-59`).
  - Heights scale with text size; no fixed-width text columns.
  - Context menus on rows (copy SHA, version, bundle id; open job; reveal artifact); credential
    row actions move into a menu with Delete styled as destructive
    (`credentials/view/credentials_page.dart:276-289`).
- **Files touched:** `apps/xp_desktop/lib/{widgets,shell,approvals,job,project_overview,credentials,theme,app}/**`
- **Acceptance criteria:** every primary action is reachable with Tab and Return; a
  `meetsGuideline(textContrastGuideline)` and `labeledTapTargetGuideline` test passes on each page.
- **Validation:** `melos run test:coverage`

### Phase U6d: Information architecture

- **Status:** Not started
- **Scope:**
  - Home: a cross-project dashboard (live, in review, running, needs you) instead of "first
    project" (`shell/view/app_shell.dart:150`).
  - Keep the selected project expanded while on engine pages (`shell/widgets/sidebar.dart:38-40`).
  - Project settings page: rename, base branch, gates (`/projects/{id}/gates`), flavor store ids,
    remove project.
  - GitHub token moves from Settings to Credentials.
  - Releases and test runs become lists with status and search instead of `XpSelect` dropdowns
    (`releases/view/releases_page.dart:84`, `tests/view/tests_page.dart`).
- **Files touched:** `apps/xp_desktop/lib/{shell,projects,project_overview,releases,tests,credentials,settings}/**`
- **Acceptance criteria:** an owner with three projects sees each one's live and in-review
  release on Home without clicking.
- **Validation:** `melos run test:coverage`

### Phase U7: Release management and rollout controls

- **Status:** Not started
- **Scope:**
  - Release timeline per version: candidate → approvals → store review → rollout → merge →
    Shorebird patches, with timestamps and who acted.
  - Rollout controls: iOS phased release pause, resume and release to all (the
    `updatePhasedRelease` adapter exists but no route uses it,
    `packages/xp_engine/lib/src/stores/apple/app_store_connect.dart:51`); Play staged rollout
    percentage up, halt and complete. All are gated actions (D-13).
  - Shorebird: promote a patch between tracks and roll back from the release page.
  - Release notes and "What to test" text kept on the release and sent with uploads.
  - CLI and MCP mirrors (`xp releases rollout …`); MCP can request, never approve.
- **Files touched:** `packages/xp_engine/lib/src/{releases,stores}/**`, `packages/xp_adapters/lib/src/stores/**`, `apps/xpd/lib/src/api/releases/**`, `packages/xp_api/**`, `apps/xp_desktop/lib/releases/**`, `apps/xp/lib/src/{commands/releases_commands,mcp/xp_tools}.dart`, `tool/e2e/fake_stores/**`
- **Acceptance criteria:** against the fake stores, pausing a phased release and raising a Play
  rollout from 10 % to 50 % each create an approval and, once approved, change the store state.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase U8: Docs, quickstart and troubleshooting

- **Status:** Not started
- **Scope:** Absorbs the docs part of Phase 19.
  - `docs/guide/quickstart.md` (app path and CLI-only/Linux/Docker path), then one page per topic:
    install, projects, credentials, workflows (inputs, expressions, gates, templates), runners,
    MCP, approvals, releases, storage, uninstall.
  - `docs/guide/troubleshooting.md` built from `skills/xpath-setup/references/troubleshooting.md`
    and `skills/xpath-release/references/failures.md`; API error hints link to its anchors.
  - README trimmed to overview, install, quickstart link and a docs index; engine internals
    (migration history etc.) move to `docs/reference/`. The site "Docs" link points at the guide.
  - Replace owner-specific values (`mataa_new_app`, team `AFBD5TBR5U`) in
    `docs/guide/try-it-locally.md` with placeholders.
  - Fix the setup skill's Docker instructions to use `ghcr.io/abdurahmanalmehdi/xpath`.
  - `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.yml` (bug asks for `xp --version` and
    the engine version) and a PR template.
- **Files touched:** `docs/guide/**`, `docs/reference/**`, `README.md`, `site/**`, `skills/**`, `.github/ISSUE_TEMPLATE/**`, `.github/pull_request_template.md`
- **Acceptance criteria:** README under 20 KB; every guide page linked from the README; a new
  user can follow `quickstart.md` alone to a first dev build.
- **Validation:** `test $(wc -c < README.md) -lt 20480`

## Not in this plan

- Build-number management: already handled by D-11 (counter seeded from stores, tags and DB).
- Store vitals and health-based automatic rollout halts (Runway): out of scope for 1.0 per
  `docs/design/DECISIONS.md:42`; revisit after U7.
- Schedule and push triggers (PRODUCT §6): a separate engine feature, not a UX fix.
- Step marketplace with versioned community steps (Bitrise): steps stay built-in (D-03).
- Timed SSH into runners after a failure (Codemagic): security review needed first.
- Web dashboard: PRODUCT §3 "later".

## Success Metrics

- Interactions from a fresh install to a first green dev build: from about 15–20 to under 12
  (U5 manual validation).
- Built-in workflows forked only to set store ids: zero (U2a).
- Failures diagnosable from the app without opening logs or the CLI: every failed step shows
  its message and fix (U1a, U4b).
- Every shortcut in `08-keyboard.md` implemented and listed in a menu (U6a).

## References

- `docs/plan/2026-10-13-feat-xpath-release-tool-plan.md` (Phase 17, Phase 19, D-11, D-13)
- `docs/design/PRODUCT.md` §2, §3, §5, §6, §8; `docs/design/DECISIONS.md`
- `docs/design/system/project/guide/07-formatting.md`, `08-keyboard.md`, `09-contrast.md`
- `docs/adr/0010-split-builtin-workflows.md`, `docs/adr/0013-named-credentials.md`
- External patterns: [Bitrise default workflows](https://docs.bitrise.io/en/bitrise-ci/workflows-and-pipelines/workflows/default-workflows),
  [Codemagic: moving from the Workflow Editor to YAML](https://docs.codemagic.io/flutter-configuration/moving-wfe-to-yaml/),
  [GitHub: re-running workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs),
  [GitHub: job summaries](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/),
  [GitHub: environments](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments),
  [EAS app versions](https://docs.expo.dev/build-reference/app-versions/),
  [Tramline store releases](https://docs-pr-18-pzox.onrender.com/using-tramline/working-pane/store-releases),
  [Shorebird rollback](https://docs.shorebird.dev/code-push/rollback/)
