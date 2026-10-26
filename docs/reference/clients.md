# Clients

The `xp` command line, `xp mcp`, the client library and the desktop app. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## The `xp` command line

`xp` mirrors the API (Phase 13). It is built on `CommandRunner`, `mason_logger` and `cli_completion`
(`xp completion`, `xp install-completion-files`), and talks to the engine only through `xp_client`.

```sh
xpd token create --name "My Mac" --kind cli                     # on the engine machine; printed once
xpd token create --name "Claude" --kind mcp                     # a second token, for `xp mcp`
xp connect http://127.0.0.1:7480 --token <cli token> --mcp-token <mcp token>
xp projects add acme/app            # or a folder on the engine machine, or git@bitbucket.org:ws/app.git
xp workflows list acme/app
xp dispatch acme/app dev-build --flavor dev --platform android
xp logs -f <job id>
```

**Connecting.** `xp connect <url> --token <token> [--mcp-token <token>]` checks that the URL is an engine of this API
version (`GET /health`, `GET /version`, no token needed) and that each token works (an authenticated
`GET /projects`), and only then saves anything. The engine URL goes to `xp.json` in `$XP_CONFIG_DIR`, else
`$XDG_CONFIG_HOME/xpath`, else `~/.config/xpath`. **The tokens never go in that file**: they go to the OS secret
store (`packages/xp_secrets`, the same code as the engine's), under the names `token.cli` and `token.mcp`. On macOS
that is the login Keychain, service `ly.abdurahman.xpath.client` (ADR 0005); on Linux it is `secrets.enc` in the config
folder, sealed with `$CREDENTIALS_DIRECTORY/xpath-master-key` or a 0600 `master.key` beside it. `XP_ENGINE_URL`,
`XP_TOKEN` and `XP_MCP_TOKEN` override what was saved, so scripts need to save nothing and never touch a Keychain;
`XP_TEST_FILE_SECRETS=1` keeps the tokens in the file store even on macOS (the end-to-end scripts use it).
`xp mcp` uses the `mcp` token and the CLI the `cli` token: they are two tokens, one per client (D-06, D-12).

**Commands.** A project is named by its id (`prj_...`), `owner/name` or just `name`; a workflow by its id
(`wf_...`) or its name. Every command takes `--json` (before the command: `xp --json projects list`) to print what
the API answered, for scripts; otherwise it prints text and tables.

| Command | API |
|---|---|
| `xp connect <url> --token T [--mcp-token T]` | `/health`, `/version`, `GET /projects` |
| `xp projects list`, `show <p>`, `add <folder or owner/name>`, `scan <p>`, `remove <p>` | `/projects` |
| `xp credentials list`, `show <c>`, `add --kind <kind> --name <name> [options of the kind]`, `rename <c> <new name>`, `replace <c> [options of its kind]`, `verify <c>`, `remove <c> [--force]` | `/credentials`; a credential is its id (`crd_...`) or its name in any case; see Credentials below |
| `xp credentials assign <c> --project <p> (--flavor <f> \| --all-flavors) [--app <path>] [--replace]`, `unassign <c> --project <p> --flavor <f> [--app <path>]` | `PUT` and `DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}`, the kind being the credential's |
| `xp workflows list <p>`, `show <p> <w> [--version n]`, `validate <p> -f file`, `create <p> <name> -f file`, `edit <p> <w> -f file` | `/projects/{id}/workflows` (`validate` exits 65 and prints `line:column: message`) |
| `xp dispatch <p> <w> [--ref --app --flavor --platform --bump --version --release-version --input k=v]` | `POST .../dispatch` |
| `xp runs show <run>`, `cancel <run>` | `/runs/{id}`; `show` names the approval a waiting run needs |
| `xp jobs show <job>`, `cancel <job>`, `resume <job> [--from-step n]` | `/jobs/{id}` |
| `xp logs <job> [-f] [--after seq]` | `/jobs/{id}/logs` (WebSocket) |
| `xp approvals list [--project --state]`, `show <a>`, `approve <a> [--reason]`, `deny <a> [--reason]` | `/approvals`; the CLI token is a `cli` token, which may decide (D-13) |
| `xp gates show <p>`, `tighten <p> <action>...` | `/projects/{id}/gates`; only the app loosens a gate |
| `xp releases list`, `show <r>`, `refresh <r>`, `status <r> <apple\|play> <state>`, `build <r>`, `merge <r>`, `rollout <r> --store <apple\|play> (--pause\|--resume\|--complete\|--halt\|--percent <n>)`, `abandon <r>`, `notes <r> [--format slack\|whatsapp]` | `/releases` |
| `xp storage report`, `free [--apply] [--category c]`, `retention [--keep n] [--log-days n]` | `/storage` (`free` is a dry run unless you pass `--apply`) |
| `xp runners pair <name>`, `revoke <runner>` | `POST /runners/pairing-tokens`, `POST /runners/{id}/revoke` (a runner is its name or id); see Runners |
| `xp runner pair`, `start` | the runner agent of this machine (`POST /runners/pair`, `GET /runners/connect`); see The runner agent |
| `xp runner install-service`, `uninstall-service`, `service-status` | the LaunchAgent or systemd unit of the runner of this machine, no engine call; see Running as a service |
| `xp artifacts list <job>`, `download <a> [-o path]` | `/jobs/{id}/artifacts`, `/artifacts/{id}/download` (checks the SHA-256 the engine sends) |
| `xp mcp` | see below |

`xp logs` without `-f` prints the log so far and stops once the engine has been quiet for 750 ms; with `-f` it follows
the job until it ends, reconnecting with the last line it printed if the connection drops, and exits 1 if the job
failed, was cancelled or was interrupted.

**Credentials.** `xp credentials` (also `xp credential`) manages the named credentials any flavor may use, one per
kind. `add` and `replace` take the options of the kind: `asc_key` `--key-id`, `--issuer-id`, `--p8 <file>` and
`--key-kind team|individual`; `apple_id` `--apple-id`; `play_sa` and `firebase_sa` `--service-account <JSON key
file>`; `keystore` `--keystore <file>` and `--key-alias`; `shorebird` and `slack` none. A secret is never an
argument: at a terminal `xp` asks for it without showing what you type, otherwise it reads it from standard input
with its flag (`--password-stdin`, `--store-password-stdin`, `--key-password-stdin`, `--token-stdin`,
`--webhook-url-stdin`), one per command since standard input is read once. A keystore's key password is optional
(empty: the store password). Without a terminal and without the flag the command stops with a usage error that
names the flag. `--kind github` is refused: the engine has one GitHub token, set in the app's Settings or with
`xpd secrets import-gh`.

```sh
xp credentials add --kind asc_key --name "Acme ASC" --key-id ABC123 --issuer-id <issuer> --p8 AuthKey_ABC123.p8
printf %s "$SHOREBIRD_TOKEN" | xp credentials add --kind shorebird --name Shorebird --token-stdin
xp credentials assign "Acme ASC" --project acme/app --all-flavors
xp credentials remove "Acme ASC" --force
```

`remove` refuses a credential that flavors use, lists them and exits 73; `--force` removes it from every flavor
first. `assign --all-flavors` leaves a flavor that has another credential of the kind as it is unless `--replace`,
and lists the flavors that kept theirs. `verify` checks the credential and every flavor that uses it, and exits 1
when a check refuses it.

**Exit codes.**

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
| 75 | `xp runner start` switched to another version (an update or a rollback); its service manager starts it again, or `xp` started the new version itself and this is its code |
| 77 | the token is rejected (`401`), or its kind may not do this (`403`) |
| 78 | not connected: `xp connect` first |

**The update check.** Once a day `xp` asks GitHub for the latest release of `AbdurahmanAlmehdi/x-path` and prints a
line on standard error if it is newer than the running version. It is a plain unauthenticated `GET` of the public
release list with a fixed `User-Agent`: it sends no version, machine, user or engine address (D-24: no telemetry),
caches the answer for a day in `update-check.json` beside `xp.json`, fails silently, runs beside the command, is never waited for more than a moment, and does not run
for `--json` or `xp mcp`. `XP_NO_UPDATE_CHECK=1` turns it off.

## `xp mcp`

`xp mcp` is an MCP server on standard input and output (Phase 13, D-12) for agents such as Claude Code:

```sh
claude mcp add xpath -- xp mcp
```

It is a thin adapter: `apps/xp/lib/src/mcp/dart_mcp_adapter.dart` is the **only** file that imports `dart_mcp`
(pinned to exactly 0.5.2, which supports stdio only: enough for 1.0; the plan moves to Streamable HTTP when 0.6 is
published). Everything else works with `McpTool`, so an API change of `dart_mcp` stays in that file. Standard output
carries MCP messages only; whatever else it has to say goes to standard error. It uses the **`mcp` token** saved with
`xp connect --mcp-token`, never the CLI's.

The tools (all of them answer with JSON text, or with `isError` and a message):

| Kind | Tools |
|---|---|
| Read | `list_projects`, `get_project`, `list_workflows`, `get_workflow`, `get_run`, `get_job`, `get_job_log_tail`, `list_artifacts`, `get_job_tests`, `get_test_baselines`, `list_releases`, `get_release`, `get_release_notes`, `list_approvals`, `get_approval`, `get_gates`, `get_storage_report`, `list_runners`, `list_credentials` (names, kinds, accounts, checks and the flavors that use each; never a secret; no tool adds, assigns or removes one) |
| Create and edit | `add_project`, `scan_project`, `update_project`, `validate_workflow`, `create_workflow`, `update_workflow` (a document is validated first; with issues nothing is saved and they come back with `line` and `column`) |
| Run | `dispatch_workflow`, `request_rollout` (asks for a rollout change; it waits at `gate: rollout` like any gated action) |

**Gates (D-13).** There is no tool to approve, deny, merge, abandon, delete or change a gate, and the engine answers
`403` to an `mcp` token that tries it by hand anyway. A gated action, such as a production release, stops at its gate:
`get_run` then shows the run as `waiting_for_approval` with `pendingApprovals`, the agent tells the owner, who approves
in the app or with `xp approvals approve <id>`, and the agent polls `get_approval` until the state is no longer
`pending`. An approval nobody decides within 24 hours expires, which counts as denied.
`tool/e2e/mcp_gate_e2e.sh` proves it against a real engine: it speaks MCP JSON-RPC to a real `xp mcp` subprocess,
dispatches `prod-release`, sees the run stop at a pending approval, gets `403` for the MCP token on approve, deny and
loosening the gate, and approves with an app token.

## The client library

`packages/xp_client` is the Dart client of the API that `xp`, `xp mcp` and the desktop app share. It depends on
`xp_api` only, has a method per endpoint (the ones in `openapi.yaml`: projects, scans, credentials, workflows,
dispatch, runs, jobs, artifacts, test runs, approvals, gates, releases, storage, runners) and 100% test coverage.
The runner methods are what the runner agent uses: `pairRunner` (no token), `connectRunner` (the WebSocket; the
caller speaks the frames of `xp_api`) and `uploadRunnerArtifact` (streams the file with its SHA-256 and size).

- **Errors.** Every error is an `XpClientException`. A non-2xx answer is an `ApiException` with the status, the
  `ApiErrorCode` of the error envelope (`null` if the answer was not one) and, for `already_decided`, the approval as
  it stands. A network failure, a timeout or an answer that is not JSON is a `ConnectionException`.
- **Events.** `watchEvents({after})` is `GET /events` with a resume cursor: it remembers the `seq` of the last event it
  passed on, and when the connection drops reconnects with `?after=<seq>` after a growing delay (1 s doubling to 30 s,
  reset by a connection that delivered something), so the listener sees each event once, in order. A `StreamOpened`
  frame starts every connection but only a stream without a cursor takes its `seq` (the head of the log). When the
  engine cannot resume (`409 resync_required` on the upgrade, or the close code 4409) the stream emits
  `EventsResyncRequired`, reconnects without a cursor and carries on: the listener reloads its state over HTTP. A
  refused token ends the stream with the `ApiException`.
- **Logs.** `followJobLogs(job, {after})` is `GET /jobs/{id}/logs` the same way: lines in order, each once, the end
  frame last. A `gap` frame (the client read too slowly) makes it reconnect from the line before the gap, so the
  lines it missed arrive after all.
- **WebSockets.** The default connector does the upgrade by hand over `dart:io`, because `WebSocket.connect` throws away
  the body of a refusal, and that body is the error envelope. Tests pass their own connector and clock.
- **Downloads.** `downloadArtifact(id)` gives the bytes as a stream; `ArtifactDownload.saveTo(file)` writes
  `<file>.part`, checks the size and SHA-256 the engine sent and renames it, or deletes it and throws.

The client is tested against fake HTTP servers (`packages/xp_client/test`) and against the real engine in-process
(`apps/xpd/test/src/client`).

## The desktop app

`apps/xp_desktop` is the macOS app (Phase 15 builds its foundation; the screens of the design follow in Phases 16a to
17). The design is in `docs/design/` (see `DECISIONS.md`): the Run Sheet tokens are copied into
`lib/theme/xp_tokens.dart`, the fonts (IBM Plex Sans and Mono, OFL, licence in `assets/fonts/OFL.txt`) and the
sidebar mark are assets, and the icons are Phosphor's.

- **Layout.** `lib/<feature>/{bloc,view,widgets}` with a barrel per feature; `flutter_bloc` with `bloc_concurrency`
  (`restartable` for the streams a bloc follows, `droppable` for commands); strings in `lib/l10n/arb/app_en.arb`
  (`flutter gen-l10n` writes `lib/l10n/gen`, which is committed); light and dark themes from the tokens
  (`lib/theme/theme.dart`); `test/helpers/pump_app.dart` pumps a widget with the theme, the strings and fakes.
- **Engines.** The app shows one engine at a time: the one on this Mac ("This Mac", `http://127.0.0.1:7480`, the
  address of `xpd serve`) or a remote one added by URL and token after the same checks as `xp connect`. Their names
  and URLs are in `engines.json` in the app's Application Support folder; their tokens (kind `app`, D-06) are in the
  login Keychain under the service `ly.abdurahman.xpath.app`, account `engine.<id>`. `EngineConnectionBloc` owns the
  active engine's `EngineSession` (client, the one event stream, status, offline cache); switching engines closes the
  session, which ends every stream it gave out, and the repository subtree is keyed on the session, so it is built
  again.
- **Offline.** The repositories (`packages/xp_repositories`) cache the last answer of each list per engine
  (`<support>/cache/<engine>/*.json`) and show it first, marked as cached. When the engine stops answering the
  connection banner says so (reconnecting, then unreachable · cached), the screens keep the cached data and every
  command is disabled until the engine is back. A locked Keychain on the engine (secrets locked) and a refused
  token have their own banner.
- **The engine on this Mac heals itself.** When "This Mac" is the active engine and turns unreachable (at launch or
  later), `LocalEngineBloc` starts it once on its own: if `/health` does not answer, `EngineAgent.restart`
  (`agentRestart` in `MacosServicesChannel.swift`) unregisters an "enabled" agent and registers it again (a
  `notRegistered` or `notFound` one is registered; one waiting in Login Items is left for the owner), the app waits
  up to 30 s for `/health`, then reconnects with the token it has in the Keychain (the engine's database is the
  same, so is the token; a new `app` token is made only if the engine refuses the old one). One automatic try per
  episode (until the engine answers again), and after a failed one the next waits 1 minute, then 2, 4, up to 30;
  each step is logged (`dart:developer`, `xpath.local_engine`). The banner then reads "The engine on this Mac isn't
  running." with **Start engine** (progress, and why it failed: Login Items approval with **Open Login Items…**, a
  copy of the app without an engine, macOS refusing, no answer in 30 s); Settings ▸ About shows "Engine on this Mac:
  Running / Not running" with the same button. Remote engines keep Retry and Engines….
- **Onboarding** (the first run, or Engines ▸ Set up this Mac…): (1) registers the bundled engine as a LaunchAgent with
  `SMAppService` (label `ly.abdurahman.xpath.xpd`, plist `Contents/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist`,
  `BundleProgram` `Contents/Helpers/xpd/bin/xpd serve`) and makes the app's token with the bundled
  `xpd token create --kind app`; (2) links the bundled `xp` (`Contents/Helpers/xp/bin/xp`) into `/usr/local/bin` if the
  user can write there, else into `~/.local/bin` (no password, no dialog; another `xp` already there is left
  alone, a link into another copy of XPath is replaced); (3) checks for Xcode (`xcode-select -p`; the Command Line Tools alone do not count), git, fvm, gh and
  Shorebird in the folders the engine's service searches. The engine and `xp` are copied into the app by the
  release build (Phase 18b); a development build has neither and says so.
- **Projects and credentials.** Add project by folder (a folder picker for the local engine, a typed path on a remote
  one), then the review of the scan (apps, flavors, findings with their fixes): keep it, scan again or remove it.
  The Credentials page lists the named credentials of the engine (name, kind, account, last check, "used by N
  flavors"), and adds, renames, replaces the secret of, checks and deletes them; deleting one that flavors use lists
  them and asks first. The engine checks a credential before it keeps it, and a `.p8` key, a service account or a
  keystore can be read from a file. Under the list, each flavor of a project shows the credential it uses for each
  kind, with the check of the assignment, and a sheet to choose an existing credential or add a new one, for this
  flavor or every flavor of the app, replacing what the others have only when "Replace existing" is ticked.
- **Project overview** (Phase 16a, concept 1A): the release in flight is the hero, drawn as a rail of its run's
  stages and then its status in each store; with nothing in flight, what is live in each store. Under it, a ledger
  per app reads each flavor from local (the pubspec at the last scan) to testing (the release in flight) to live in
  the App Store and Google Play, then the names of its credentials (a click opens the sheet that assigns
  them); the console docked at the bottom follows the log of the job
  that runs (⇧⌘C hides it). The scan of the project is one click away (Scan).
- **Dispatch** (⌘N): the sheet picks a workflow, the app, flavors, platforms, the ref and the version bump, and
  previews what would run: each stage's jobs, where each lands (the engine, or the least loaded runner that can run
  it and the slot it would take) and which gates it stops at. The preview is worked out in the app
  (`DispatchPreview.plan` in `xp_repositories`) from the workflow, the runners, the gates and the credentials the
  engine returns, the same way the engine reads them; the engine still plans the run when it is dispatched. The
  button reads "Dispatch N jobs ⌘↩"; Return never dispatches.
- **Job view** (concept 2A): the run's pipeline graph over the steps and the log of one job (click a node to show
  another). The log is grouped by step, with terminal colours, a filter (⌘F), jump to error (⌘E), wrap, timestamps
  and follow (⌘↓); it resumes from the last line it holds, also after the job is resumed. Cancel (⌘.) asks first and
  says what stops, what is kept and what never starts; a failed, cancelled or interrupted job offers "Re-run all"
  (⌘R) and "Resume from <step>" (⌥⌘R, from the step picked in the step list or the first unfinished one).
- **Releases** (Phase 16b, concept 3A; Releases under the selected project, or "Open release" on the overview): the
  release shown (the one in flight, or the one picked in the toolbar) is the hero, with Merge beside it and why it
  is not open yet. Under it an App Store lane and a Google Play lane show the steps of each review, from the store
  statuses the engine keeps (Refresh asks the stores now). A store the engine cannot read (no App Store Connect key
  or Play service account for the flavor) gets "Mark approved" / "Mark live" (D-14, D-15); a rejected build offers
  "New build, same version…", which opens the run it starts. Then the timeline (what the engine keeps: the
  dispatch, each build, the last change in each store, the approvals of its runs), the release notes with "Copy for
  Slack" / "Copy for WhatsApp", the `min_version_*` reminder (the engine does not know whether a release is a forced
  update, so it says "if") and the release PR.
- **Approvals** (D-13): the needs-you bar of a project (the approval that expires first; "Review… ⇧⌘A", "Deny…"), the
  inbox (Approvals in the sidebar, with the count of what waits; Pending, Decided, Expired) and the confirmation
  sheet, the only place the app decides. The sheet says what the approval is bound to and "If you approve…"; Approve
  takes ⌘↩ (or a click) once a one-second arming delay is over, Return never approves, and an approval another device
  decided first (`409 already_decided`) or that expired ends the sheet with who decided it.
- **Notifications and the menu bar extra**: an approval that starts waiting while the app runs posts a macOS
  notification ("Review…", "Later"); the menu bar extra (`XPathTemplate`, a dot while something waits) lists every
  approval that waits and "Open XPath". Neither decides anything: "Review…" opens the confirmation sheet in the main
  window, a click on the notification opens the inbox. macOS asks for permission to notify the first time one is
  posted. Both go through `NeedsYouAlerts` in `packages/xp_macos_services` (channel `ly.abdurahman.xpath/needs_you`,
  implemented in `MacosServicesChannel.swift`; a native status item with an `NSMenu`); the tests use
  `FakeNeedsYouAlerts`.
- **macOS services** (`packages/xp_macos_services`) are interfaces with fakes (`package:xp_macos_services/testing.dart`):
  the LaunchAgent and the Keychain go through the channel `ly.abdurahman.xpath/macos_services`, implemented in
  `apps/xp_desktop/macos/Runner/MacosServicesChannel.swift`; the `xp` link, the tool check and the bundled engine are
  Dart. No test registers an agent, touches a Keychain or writes outside a temporary folder.
- **No sandbox.** XPath ships outside the Mac App Store (D-23), and it runs the bundled engine, links `xp` and checks
  tools, so the app is not sandboxed (`macos/Runner/*.entitlements`).
- **Settings** (Phase 18c; Settings in the sidebar, or XPath ▸ Settings… ⌘, in the app menu, which reaches Dart over
  the channel `ly.abdurahman.xpath/app_menu`): the app's version, the engine shown with its version and connection,
  and the engine's login item on this Mac. **Command line tool**: where `xp` is linked, or that it is not, that
  another `xp` is in the way, or that the link points into another copy of XPath (an old or moved app, a build
  folder); "Link xp" (or "Link xp again") links it as onboarding does (`CliLinker`, `FakeCliLinker` in the tests).
  A build without a bundled `xp` says so and offers nothing. **GitHub**: the engine's GitHub token, which adding a project needs: what
  GitHub says of it (the login, or why it refused it), a field to paste a new one ("Check and save"), "Import from
  GitHub CLI" (`gh auth token` on the engine machine) and "Remove token". Add project asks the engine for the token
  when it opens and after a failed add; without one (or with one GitHub refuses) it says so and "Connect GitHub…"
  opens this section with the cursor in the field.
- **Remove XPath** (Settings): a sheet with "Also delete engine data" and "Also delete Keychain items". Confirmed, it
  (1) revokes every runner of the engine on this Mac through its API while it still runs (`revokeLocalRunners`),
  (2) unregisters the engine's login item (`SMAppService.unregister`, which makes launchd stop it) and waits until
  `/health` stops answering, (3) removes the `xp` link only where it points into this app, (4) if asked and only
  once the engine stopped, deletes the engine's data folder (`~/Library/Application Support/XPath`) and the app's
  Application Support folder (engine list and cache), and (5) if asked, deletes every Keychain item whose service is
  `ly.abdurahman.xpath` or under it: the runner lists them (names only, never a value), the app's own items go
  through `SecItemDelete`, the engine's through `security delete-generic-password` (which made them). A step that
  fails is shown with what macOS or the engine said and the others still run. The sheet then offers "Move to Trash
  and quit" (`NSWorkspace.recycle` of the bundle) or "Quit XPath", and says to drag the app to the Trash when the
  Trash refuses. All of it goes through `xp_macos_services` interfaces (`EngineAgent.unregister`,
  `CliLinker.unlink`, `DataWiper`, `KeychainWiper`, `RunningApp`, `AppMenu`) with fakes; no test removes anything
  real. An engine started with `--data-dir` or `XPATH_DATA_DIR` elsewhere keeps that folder. Not built (owner,
  Goal 3): Sparkle and the appcast, and the Homebrew cask with its `zap` stanza.
