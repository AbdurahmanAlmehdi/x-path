---
title: "feat: make a first remote runner useful"
type: feat
date: 2026-10-21
---

## feat: make a first remote runner useful

## Overview

Feedback from pairing a first remote runner
([2026-10-20 feedback](../feedback/2026-10-20-remote-runner-onboarding.md)). The setup was an
AWS Ubuntu 24.04 box against an engine on the owner's Mac (`127.0.0.1:7480`, engine 1.1.2),
building two Flutter apps that live on Bitbucket. Pairing worked, but the runner was not useful
yet. This plan turns each finding into pull requests that ship on their own, in the order they
pay off.

The owner asked for two things in particular: a runner should get its build tools (section 1),
and it should stay connected without someone watching it (section 2). Both come first.

## What the code does today

The feedback was checked against the code. Some of what it describes is already in place. Some
of it works differently from how it looked from outside.

| Finding | What the code does | So the work is |
|---|---|---|
| "No `flutter` capability" | `flutter` only means `git --version` runs (`packages/xp_engine/lib/src/runners/runner_probe.dart:104`). The runner clones the pinned SDK into `<data dir>/toolchains/flutter/<version>` when a job needs it (`apps/xp/lib/src/runner/runner_steps.dart:55-65`). A stock Ubuntu box with git most likely offered `flutter` and lacked `android`. | Say what is offered. Make `flutter` check what Flutter needs on Linux (curl, unzip, xz). |
| `android` | Offered when one of `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `~/Android/Sdk` or `~/Library/Android/sdk` contains `platform-tools`, `cmdline-tools` or `build-tools`. **No JDK check**, although `capability.dart:5-17` documents `android` as "Android SDK and a JDK". | Probe for a JDK. Install both (image, installer flag). |
| Nothing says what is missing | `RunnerProbe.evaluate` keeps only the capability set; the stdout, stderr and status of each result are dropped (`runner_hub.dart:711`). The runner never learns what the engine derived. | Keep a reason and a fix for each missing capability. Send them to the runner. Print them. |
| Reconnect with backoff | Already implemented. It retries forever, starting at 1 s, doubling to 60 s, with jitter, and resets on `welcome` (`runner_agent.dart:180-221`, `backoff.dart`). It stops only on 4003 revoked, 4001 replaced or a refused credential. The systemd unit has `Restart=on-failure` and the LaunchAgent has `KeepAlive`. | Prove it for hours offline. Fix what goes wrong over hours (below). |
| Leased jobs follow the loss rule | The engine side is correct: the lease outlives the connection, `LeaseSweeper` runs, `waiting_for_resume` is set. **The runner has no lease clock.** It ignores `heartbeat_ack` (`runner_agent.dart:343-344`) and keeps running a lost job, buffering its output in memory without a limit, until it reconnects and is told `cancel`. | Add a runner-side lease fence. |
| Pairing prints `127.0.0.1` | The desktop sheet uses the URL of the app's engine profile, which for "This Mac" is the hardcoded `localEngineUrl` (`engine_profile.dart:9`). `xp runners pair` prints only the token. The engine has no notion of the URL runners use. | Add a runner URL setting to the engine, used by both pairing flows. |
| `xp runners list` | `GET /runners`, `XpClient.listRunners()`, the `Runner` schema and a contract test all exist, with status, capabilities, slots, `jobIds`, `lastHeartbeat`, version, os and arch. Only the CLI command and an MCP tool are missing. | Small. |
| Engine log on connect/disconnect/refuse | `runner.connected` and `runner.disconnected` events exist. Nothing writes a log line, and refusals (401/403/426, close codes 4001/4008/4400) leave no trace at all. | Log lines from serve, plus a refusal callback on the route. |
| Bitbucket | GitHub is assumed in every layer: `GitHubRemote.parse` (`project_service.dart:174-177`); `project.github_repo_id INTEGER NOT NULL UNIQUE` keys the project, the engine mirror, the runner cache, the lease protocol, housekeeping and `ReleaseWorktree`; the engine authenticates git only through a `https://github.com` credential helper. The 1.0 plan lists Bitbucket as a non-goal. | An ADR, then four PRs (section 4). |
| `install --runner` ends with the completion hint | `install.sh:176-180` already prints `xp runner pair ...` and `xp runner install-service` for `--runner`. The completion hint most likely comes from `cli_completion` auto-installing when the installer runs `xp --version` (`install.sh:148-155`). | Check on a clean box; turn auto-install off for that call; add the capability check to the next steps. |
| "Engine, CLI and runner each warn that 1.1.3 is out" | Only `xp` checks GitHub for a newer release (`apps/xp/lib/src/update/update_check.dart`); xpd has no such check. A runner prints it on exit, which is misleading because a runner updates itself to **its engine's** version between jobs (`runner_updater.dart`). The engine does not refuse a runner on another version. Clients need the same `apiVersion` (`'1'`). D-24's "one minor version behind" is not implemented; the actual rule is looser. | Write the rule down. Stop the GitHub nag in `xp runner`. |

## Decisions for the owner

The plan assumes the first option of each.

| # | Question | Recommended | Alternative |
|---|---|---|---|
| Q1 | A runner's lease has run out while it was unreachable. What happens to the step that is running? | Stop it as a `cancel` frame would. The lease is the single source of truth (D-08), the engine has already decided, and side-effect steps ask `alreadyDone` on resume. | Let a running side-effect step finish but start nothing after it. This saves a half-done Shorebird upload, but the runner keeps acting on a lease it no longer holds. |
| Q2 | Where does the runner URL live? | An engine setting in the database, set with `xp runners url <url>` or in the app (Settings → Runners), returned with every pairing token. | `xpd serve --public-url`. That is simpler, but the app's own LaunchAgent passes no flags, so the app could not set it. |
| Q3 | First step for other git hosts: which workflows may run? | Only workflows with no `github.*` and no `git.push` step: the built-in `dev-build` and `test`, and custom ones like them. The engine can push only with the GitHub token. | Also allow `git.push` and `git.tag` over the engine's SSH key. That makes `prod-release` almost work, but its `finalize` still needs `github.createPr`. |
| Q4 | Which recipe does the README name for reaching the engine? | Tailscale with `tailscale serve`: TLS on a `*.ts.net` name, no public port, and the engine stays on loopback. Cloudflare Tunnel and an autossh LaunchAgent are listed as alternatives. | Build a command (`xpd expose ...`). Not now; the docs come first. |
| Q5 | How do we relax `project.github_repo_id NOT NULL`? | A table rebuild (SQLite's 12-step procedure) in a migration that runs with foreign keys off. This needs a small extension to the migration runner. | Keep the column and give non-GitHub projects negative synthetic ids. That needs no rebuild, but a fake GitHub id ends up in the API and in step inputs. |

## Pull requests

Each PR follows CONTRIBUTING: tests in the same PR, `openapi.yaml` and a contract test for any
API or frame change, and a new migration with its golden for any schema change. The migration
numbers below (v15, v16) are given in merge order and are assigned when the PRs land.

| PR | Feedback | Size | Depends on |
|---|---|---|---|
| 1. The runner says what it offers and why not | 1, 5 | M | — |
| 2. `xp runner doctor` | 1 | S | 1 |
| 3. `xp runners list`, `list_runners`, engine log lines | 3 | S | 1 (prints the reasons) |
| 4. A runner URL for pairing | 2 | M | — |
| 5. Offline for hours: lease fence and quiet reconnects | 2 | M | — |
| 6. Docs: reaching the engine from another machine | 2 | S | 4 |
| 7. `install.sh --with-android` and the next steps | 1, 5 | M | 2 |
| 8. The `xpath-runner` image | 1 | M | 7 |
| 9. Versions: what must match | 5 | S | — |
| 10a–10d. Projects on any git host | 4 | L | ADR 0014 |

PRs 1, 4, 5 and 9 can be worked on in parallel.

### PR 1: The runner says what it offers and why not

**Goal.** At start, the runner prints what it offers and, for each capability it does not offer,
the reason and the fix. The engine prints the same reasons for itself.

- **Probe reasons** (`packages/xp_engine/lib/src/runners/runner_probe.dart`).
  `RunnerProbe.evaluate` returns `ProbeFindings{capabilities, operatingSystem, missing}`, where
  `missing` is a list of `MissingCapability{capability, reason, fix}`. The reason comes from the
  probe result that failed: not installed, a non-zero exit with the first line of stderr, a
  timeout, or skipped on this OS. Examples:
  - `android`: "no Android SDK in ANDROID_HOME, ANDROID_SDK_ROOT or ~/Android/Sdk". Fix: "install
    the command-line tools (install.sh --with-android) or set ANDROID_HOME".
  - `android`: "no JDK: java not found". Fix: "install JDK 17 (apt-get install
    openjdk-17-jdk-headless) or set JAVA_HOME".
  - `ios-sign` is not listed on Linux, and `swift-linux` is not listed on macOS: skipped on this
    OS is not a missing capability.
- **Better rules.**
  - `android` also needs a JDK: `$JAVA_HOME/bin/java -version`, else `java -version`, version 17
    or later. `JAVA_HOME` is already passed to the build (`build_android.dart:95-105`).
  - On Linux, `flutter` also needs `curl`, `unzip` and `xz`, which the SDK download needs on
    first run. This is one `sh -c 'command -v ...'` probe command that names the tools it did not
    find.
  - `LocalCapabilities` (`scheduler/local_capabilities.dart`) and `DirectoryAndroidSdk` get the
    same rules and return the same `missing` list, so the engine and the runner never disagree.
- **Protocol.** A new `EngineFrame` `probed` `{capabilities, missing}`, sent right after
  `_probed` stores the capabilities (`runner_hub.dart:704-742`). A runner ignores unknown frame
  types, so an older runner keeps working. Add the schema to `openapi.yaml` and the frame to the
  "every engine frame" contract test (`apps/xpd/test/contract/runners_contract_test.dart:324`).
- **API.** `Runner` gains `missing` (optional, present while the runner is online, kept in memory
  only, so there is no migration). The desktop runners table shows it as a tooltip on
  "Capabilities".
- **Output.**
  - `xp runner start` prints, after the connect line:

    ```
    Runner "AWS Instance" connects to https://mac.tailnet.ts.net.
    Nothing was left by an earlier run.
    Connected. The engine runs 1.1.2; this runner offers flutter, 2 slots.
    No android: no JDK: java not found. Install JDK 17 (apt-get install openjdk-17-jdk-headless) or set JAVA_HOME.
    ```

    It prints this again only when the set changes.
  - `xpd serve` keeps `xpd runs jobs here with 2 slots and flutter, android, ios-sign` and adds
    one `no <capability>: ...` line per missing capability.
- **Tests.** `runner_probe_test` covers each reason. The hub tests check that `probed` follows
  `probe_result`. `runner_agent_test` checks the printed lines and checks that a change of set is
  printed once. The xpd serve test checks the `no ...` lines.

### PR 2: `xp runner doctor`

**Goal.** Answer "will this machine get jobs?" without connecting, and with no engine at all.

```
xp runner doctor [--data-dir <dir>] [--git-host github.com]...
```

- It runs `RunnerProbe.commands` through the runner's own `ProbeExecutor` and evaluates them with
  `RunnerProbe.evaluate`. This is the same code the engine runs on the results, so doctor and the
  engine agree by construction.
- It also checks:
  - `perl`, which the process supervisor needs (exit 69 today).
  - The data directory, and whether the runner is paired: `runner.json`, and whether the
    credential can be read.
  - When paired, whether the engine answers `GET /version` with the same API version. Unpaired,
    this check is skipped and says so.
  - The service state (`service-status`).
  - `ssh -T git@<host>` for each `--git-host` (default `github.com`), with `BatchMode=yes`. It
    reads the output rather than the exit code: GitHub exits 1 on success, Bitbucket exits 0.
- Output is one line per check (`ok`, `missing`, `skipped`) followed by the fix. Exit 0 when the
  runner can take at least one kind of job, 1 otherwise. `--json` follows the global flag.
- **Tests.** Fake `ProcessRunner` for the probe and ssh, a temporary data directory, and a fake
  engine for `/version`. `command_runner_test` lists the new subcommand.

### PR 3: `xp runners list`, `list_runners`, engine log lines

- **CLI.** `xp runners list [--all]` in `runners_commands.dart`, modelled on `ProjectsListCommand`
  (`renderTable`, `formatTime`, the empty hint "No runners. Pair one: xp runners pair <name>",
  and `--json` as `[runner.toJson()]`).
  - Columns: NAME, ID, STATUS, LAST SEEN, CAPABILITIES, SLOTS (`busy/slots`), JOBS, MACHINE.
  - STATUS uses the desktop labels (`apps/xp_desktop/lib/runners/widgets/runner_labels.dart`):
    idle, busy, updating, lost (offline and holding jobs), offline, revoked. Move that logic into
    `xp_api` (a `Runner` extension) so the CLI and the app share it.
  - Revoked runners are hidden unless `--all` is given.
  - Update `command_runner_test.dart:178-183`.
- **MCP.** A `list_runners` tool in `xp_tools.dart`, with `readOnly: true` and no inputs, like
  `list_projects`. Add runners to `mcpInstructions`. Update the tool list test, the README table
  and `skills/xpath-release/references/mcp-tools.md`.
- **Engine log.**
  - **Connect and disconnect.** `serve_command.dart` subscribes to the `EventLog` for
    `runner.connected`, `runner.disconnected` and `runner.capabilities_changed` and writes, for
    example:
    - `runner "AWS Instance" connected: xp 1.1.2, linux x86_64, 2 slots, flutter (no android: no JDK)`
    - `runner "AWS Instance" disconnected (no frame for 90 s)`

    `xp_engine` stays free of logging.
  - **Refusals.** `RunnerConnectRoute` and `RunnerHub` get an `onRefused(String)` callback, like
    the hub's `onError`, and serve writes `refused a runner connection from <address>: <why>`.
    The reasons:
    - an unknown or revoked credential: the 401 from `authMiddleware` when the path is
      `/runners/connect`
    - the wrong token kind (403)
    - not a WebSocket upgrade (426)
    - replaced (4001)
    - timeout (4008)
    - a protocol error (4400)
  - Disconnect lines carry the close code's meaning.
- **Tests.** CLI tests with an online sample runner (`test/helpers/samples.dart` has only a
  revoked one), the MCP tool test, and an xpd test that pairs, connects and drops a `RunnerClient`
  and checks the three lines.

### PR 4: A runner URL for pairing

**Goal.** Both pairing flows print a command that works on the runner machine.

- **Storage.** Migration v15: `engine_setting(key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT`,
  with its golden. `housekeeping_setting` is the same shape but is named for housekeeping, so it
  is not reused.
- **API.**
  - `GET /settings/runner-url` and `PUT /settings/runner-url` (`{url}` or `{url: null}`). Only
    `app` and `cli` tokens may change it; `mcp` may read it.
  - `PairingToken` gains `engineUrl`: the runner URL, or null when none is set.
  - The URL is validated as an absolute `http` or `https` URL with no user info. A plain `http`
    URL that is not loopback, a tailnet address (`100.64.0.0/10`) or a `*.ts.net` name is
    accepted with a warning in the response, because the socket carries signing material.
- **CLI.**
  - `xp runners url [<url> | --clear]` shows or sets the URL.
  - `xp runners pair <name>` prints the whole command:

    ```
    On the runner machine, within 15 minutes:
      xp runner pair --engine https://mac.tailnet.ts.net --token xpp_...
    ```

    Without a runner URL it uses the CLI's own engine URL. When that is loopback it adds "This
    address only works on this machine. Set the address runners use: xp runners url <url>" and a
    link to the README section from PR 6.
- **App.** The pair sheet (`pair_runner_sheet.dart`) uses `engineUrl` from the response, else
  the profile URL with the same loopback warning and a field to set the runner URL in place.
  Settings → Runners gets the same field.
- **Tests.** The migration golden, route tests (token kinds, validation, warning), the contract
  test, the CLI output, and a bloc/widget test for the sheet with and without a runner URL.

### PR 5: Offline for hours: lease fence and quiet reconnects

**Goal.** A runner may be offline for hours (the Mac asleep, the tunnel down). It comes back
within about a minute of the engine, and it never keeps working on a job the engine has already
given up.

- **Lease fence (Q1).**
  - The runner records `leaseUntil` from each `heartbeat_ack`; today it ignores it.
  - When a lease's `leaseUntil` plus 15 s has passed with no ack, the runner handles the job as a
    `cancel` frame would: it stops the process groups, wipes the secrets and reports nothing more
    (`_cancelled`, `runner_agent.dart:495-510`). The 15 s covers one sweep (every 10 s) plus clock
    skew.
  - The time is measured with a monotonic `Stopwatch` from when the ack arrived, so the
    engine's clock and the runner's need not agree.
  - The runner logs `Lost the lease of job <id> while the engine was unreachable; stopped it.`
- **Bounded outbox.** Once a lease is fenced, its outbox entries are dropped. Until then, the
  outbox keeps its chunks as it does today. A fenced job is at most 90 s + 15 s of output.
- **Quiet reconnects.** One line when the connection is lost. One line on the first failed
  attempt. Then at most one line every 10 minutes ("The engine has been unreachable for 2 h 10
  min; still trying every 60 s"). One line when it is back ("Connected again after 3 h 12 min").
  Hours offline then fill a service log with a few dozen lines rather than thousands.
- **Prove it.**
  - Agent tests with a fake clock: the engine is unreachable at start, a drop mid-job is longer
    than the lease, a drop is shorter than the lease (the job continues, as today), and the log
    rate stays within the limit.
  - A new `tool/e2e/runner_offline_e2e.sh`, modelled on `runner_loss_e2e.sh`:
    1. start a runner under a short-lease test hook
    2. stop the engine (SIGSTOP, then SIGKILL) for longer than the lease
    3. check that the runner fenced the job
    4. start the engine again
    5. check that the runner reconnects without a restart and that the job follows the loss rule
  - Run the same check once by hand under the systemd unit and the LaunchAgent. The result goes
    in the PR description.
- **Docs.** The README's runner agent section says that a runner may be offline for hours, what
  happens to its jobs, and that the engine Mac should not sleep while runners have work. D-10
  already covers the Mac mini; a laptop engine is the owner's choice.

### PR 6: Docs: reaching the engine from another machine

A new README section, "Reaching the engine from a runner", plus a short version in
`skills/xpath-setup/SKILL.md`. It names one setup and gives two alternatives (Q4).

1. **Tailscale (recommended).** Tailscale on both machines. On the engine Mac,
   `tailscale serve --bg http://127.0.0.1:7480` publishes `https://<mac>.<tailnet>.ts.net` with a
   real certificate (HTTPS certificates must be on in the tailnet). WebSockets pass through.
   - The engine keeps listening on loopback, nothing is public, and the traffic is encrypted
     twice.
   - Then `xp runners url https://<mac>.<tailnet>.ts.net`.
   - The exact commands are checked against the current Tailscale docs when the PR is written.
2. **Cloudflare Tunnel.** `cloudflared` on the engine machine maps a hostname to
   `http://127.0.0.1:7480`.
   - The engine becomes reachable from the internet, protected by its bearer tokens (every route
     but `/health` and `/version` needs one).
   - Cloudflare Access in front is **not** supported yet: the runner cannot send the
     service-token headers. A follow-up could add `XP_ENGINE_HEADERS`.
3. **SSH reverse tunnel.** autossh as a LaunchAgent on the engine Mac:

   ```sh
   autossh -M 0 -N -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -R 127.0.0.1:7480:127.0.0.1:7480 user@runner
   ```

   - Ship the plist as `tool/release/macos/ly.abdurahman.xpath.tunnel.plist` with placeholders.
   - The runner URL is then `http://127.0.0.1:7480` on the runner, and SSH encrypts the traffic.
   - It only works for a runner whose SSH port the Mac can reach, one tunnel per runner.

The section also says what not to do: `--host 0.0.0.0` without TLS in front.

### PR 7: `install.sh --with-android` and the next steps

- **`--with-android`** (`XPATH_WITH_ANDROID=1`), on Debian or Ubuntu only (`/etc/os-release`
  `ID` or `ID_LIKE`); elsewhere it fails with a clear message.
  - It installs `openjdk-17-jdk-headless git openssh-client curl unzip xz-utils zip perl` with
    `apt-get` (through `sudo` when not root; without either it prints the command and stops).
  - It downloads the Android command-line tools, pinned by version and SHA-256 in the script.
  - It accepts the licences with `sdkmanager --licenses`.
  - It installs `platform-tools`, one `platforms;android-N` and one `build-tools;X`. The Flutter
    Gradle plugin downloads other versions on demand once the licences are accepted.
  - The SDK goes to `--android-sdk <dir>` (default `~/Android/Sdk`). That is already a place the
    probe and Flutter look, so no `ANDROID_HOME` is needed. When the directory is elsewhere, the
    installer prints the `ANDROID_HOME` line, and `xp runner install-service` writes it into the
    unit when it is set at install time.
  - Running it again skips what is already installed.
- **Next steps** for `--runner`:
  1. `xp runner doctor` (PR 2), which shows the capabilities now.
  2. The pair command, with a note that `xp runners pair <name>` prints it in full (PR 4).
  3. `xp runner install-service`.
- **Completion hint.** Reproduce on a clean Ubuntu 24.04 container. If `cli_completion`'s
  auto-install fires on the installer's `xp --version` check, turn auto-install off for
  `--version` (override `enableAutoInstall` in `XpCommandRunner`) so the hint does not appear in
  the middle of the install.
- **Tests.** Extend `install_test.sh` with a fake `apt-get`, `sudo` and `sdkmanager` on `PATH`
  and a local `file://` command-line tools zip, covering a wrong SHA-256, a non-Debian
  `os-release` and a re-run. Run a real install once in an `ubuntu:24.04` container in CI (see
  PR 8, which does it as a side effect).

### PR 8: The `xpath-runner` image

- **`Dockerfile.runner`, based on `ubuntu:24.04`.** It runs `install.sh` from the bundle with
  `--archive /bundles/linux-x64 --runner --with-android --android-sdk /opt/android-sdk
  --no-service`, so the image is built by the installer and tests it.
  - Flutter is not in the image: the runner clones the pinned SDK into the volume at
    `/data/toolchains/flutter/<version>` as it does today. One image serves every Flutter
    version, and the volume caches them.
  - It runs as `xpath` (uid 10001) with `XP_RUNNER_DATA_DIR=/data`, `HOME=/data/home` (so
    `~/.ssh` and `~/.gradle` persist in the volume), `ANDROID_HOME=/opt/android-sdk` and
    `XP_RUNNER_MANAGED=1`.
  - **amd64 only:** Google ships no Linux arm64 Android build tools (`aapt2`).
- **Entrypoint `xpath-runner`.**
  - It runs `/data/current/bin/xp` when it exists, else the image's `xp`. A runner that updated
    itself to its engine's version keeps that version across container restarts.
  - Exit 75 (switched version) is passed on, so `--restart on-failure` starts it again.
  - Exits 77 (revoked), 73 (replaced) and 78 (not paired) print why and exit 0, so Docker does
    not restart a runner that must not run. This matches `RestartPreventExitStatus` in the
    systemd unit.
  - Usage:

    ```sh
    docker volume create xpath-runner
    docker run --rm -it -v xpath-runner:/data ghcr.io/abdurahmanalmehdi/xpath-runner \
      runner pair --engine https://mac.tailnet.ts.net --token xpp_...
    docker run --rm -v xpath-runner:/data ghcr.io/abdurahmanalmehdi/xpath-runner runner doctor
    docker run -d --name xpath-runner --restart on-failure -v xpath-runner:/data \
      ghcr.io/abdurahmanalmehdi/xpath-runner            # CMD: runner start
    ```

    The SSH key for the source (ADR 0009) is made in the volume with `docker exec xpath-runner
    ssh-keygen -t ed25519`, or mounted read-only. `doctor` prints the public key to add as a
    deploy key.
- **CI.** A `docker-runner` job in `.github/workflows/release.yml` after `bundles`, like `docker`.
  It builds the image, runs `xp runner doctor --json` in it and checks that `android` and
  `flutter` are offered, then pushes `ghcr.io/abdurahmanalmehdi/xpath-runner:<version>` (and
  `:latest` unless it is a pre-release).
- **Docs.** README "Releases and installation" → Docker gets the runner image. Also correct the
  engine `Dockerfile` comment "no Flutter": it has git, so its local runner reports `flutter`.
  Either set `--slots 0` there or say so.

### PR 9: Versions: what must match

- **README, new short section "Which versions work together":**
  - A runner always runs its engine's version. It updates itself between jobs, so a runner and an
    engine on different versions are supported only for the minutes the update takes.
  - The app, the CLI and `xp mcp` need an engine with the same API version. Every 1.x release is
    API 1, so they need not be upgraded together.
  - Upgrade the engine first; runners follow by themselves.
- **Correct D-24.** Its "accepts an engine one minor version behind" is not what the code does.
  Change the 1.0 plan's D-24 row to the rule above (or open an issue to implement D-24 as
  written, if the owner prefers it).
- **`xp runner` stops the GitHub update check** (skip it for the `runner` command tree in
  `command_runner.dart:168-173`, as for `mcp`). In its place, `xp runner start` prints "The
  engine runs 1.1.3; this runner updates to it between jobs" when the versions differ (PR 1's
  connected line).
- Find where the "engine" 1.1.3 warning came from. xpd has no update check, so it was probably
  `xp` on the Mac or the app's Sparkle prompt. If it came from xpd, apply the same treatment.

### PR 10: Projects on any git host

First write **ADR 0014 "Projects on any git host"**, which refines D-05 and ADR 0009 and removes
"GitLab or Bitbucket" from the 1.0 non-goals. What it decides:

- **Identity.**
  - A project has a `host` (`github.com`, `bitbucket.org`, any SSH host, or `local` for
    `file://`) and a `source_key`. The key is a stored, opaque string that keys the engine
    mirror, the runner cache and the worktrees.
  - For GitHub the key is the repository id in decimal, so existing `mirrors/<id>.git` folders
    stay where they are. For other hosts it is `h` plus 16 hex digits of the SHA-256 of the
    normalised remote URL, fixed when the project is added.
  - `github_repo_id` becomes nullable; it is present only for GitHub projects.
- **Source.**
  - Other hosts are added by an SSH URL (scp-like or `ssh://`) or a `file://` URL.
  - An HTTPS remote that is not GitHub is refused with "use the SSH URL; XPath has no
    credentials for <host> over HTTPS".
  - The engine fetches with its own SSH key, using the runner's
    `GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=30'`. The engine machine needs a key
    that can read the repository, as a runner does.
- **What runs (Q3).**
  - A workflow with a `github.*` or `git.push` step is refused at dispatch on a non-GitHub
    project, with an error that names the host, the step and the workarounds (`dev-build`,
    `test`, or a private GitHub mirror).
  - Pull requests on Bitbucket are later work.

**10a. Schema and identity** (L).
- Extend the migration runner (`sqlite_database.dart`) with migrations that run with
  `PRAGMA foreign_keys=OFF` outside the per-migration transaction. The runner runs
  `PRAGMA foreign_key_check` before it commits and fails the migration on any row.
- Migration v16 rebuilds `project` following SQLite's 12-step procedure, with `host`,
  `source_key UNIQUE NOT NULL` and a nullable `github_repo_id`. Existing rows get
  `host='github.com'` and `source_key=github_repo_id`.
- The golden is `v16.sql`. Add a test that migrates a populated v15 database (apps, flavors,
  jobs, runs, approvals) and finds every row and foreign key intact. The pre-migration backup
  (`xpath.db.bak-v15`) is already made.
- In `ProjectRecord`, `Project` (xp_api) and `openapi.yaml`, `githubRepoId` becomes `int?`, and
  the records gain `host` and `sourceKey`. `findBySourceKey` replaces `findByGithubRepoId`
  wherever the key is meant.
- An app one minor version behind cannot read a project without `githubRepoId`. PR 9's version
  section says so.

**10b. Mirrors, runner cache and the lease** (M).
- In `GitService.ensureMirror`, `GitMirror`, `CliGitService` paths, `ReleaseWorktree`
  (`mirror.key`; still read `mirror.githubRepoId` from jobs serialised before the upgrade),
  `LeasePaths` and housekeeping (`directory_data_files.dart`: the regex
  `^(\d+|h[0-9a-f]{16})\.git$`; the planner looks up by key), replace `githubRepoId` with
  `sourceKey`.
- `LeaseRepository` gains `cacheKey`, and `githubRepoId` becomes optional.
  - Runners update to the engine's version before they take offers, so both ends change
    together.
  - Contract test.
- `RemoteCheckoutStep._explain` becomes host-aware: "run `ssh -T git@bitbucket.org` once",
  "add this runner's SSH key as an access key of <workspace/repo> (Bitbucket: Repository
  settings, Access keys)", "<host> has no commit".
- `CliGitService` sets the BatchMode `GIT_SSH_COMMAND` for non-GitHub remotes.

**10c. Adding, scanning and dispatching** (M).
- `ProjectService.add` and `_addFolder` keep `GitHubRemote.parse` for GitHub. For any other
  origin they:
  1. derive the host and `owner/name` from the URL path, keeping more than two segments for
     GitLab subgroups
  2. run `git ls-remote --symref <url> HEAD` with the engine's SSH environment to prove access
     and read the default branch
  3. refuse with the host-aware fix on failure
  4. register the project without any GitHub call
- `scan` skips `getRepoById`, which follows renames, when `host != github.com`.
- Dispatch refuses as decided above (`workflow_dispatcher.dart:133-134` already computes the
  step kinds). The desktop `dispatch_preview.dart` and the MCP `dispatch_workflow` show the same
  reason.
- The CLI help, the `add_project` tool description ("Add a GitHub repository") and the error
  "is not on GitHub" change to match.
- **Tests:**
  - replace `project_service_test.dart:178` with tests for a `file://` and an SSH origin, an
    HTTPS non-GitHub origin and `ls-remote` failures
  - dispatcher refusal tests
  - a new `tool/e2e` scenario that runs a `dev-build` on a runner from a `file://` bare
    repository, with no GitHub token on the engine

**10d. The app** (S).
- The add-project page's GitHub token notice says it is needed for GitHub projects only.
- Projects show their host.
- The workflows that cannot run are greyed out with the reason.
- Places that split `fullName` on `/` handle more than two segments.

## Success criteria

- A fresh Ubuntu 24.04 box with `install.sh --runner --with-android`, or the `xpath-runner`
  image, offers `flutter` and `android`, and `xp runner doctor` says so | verify: PR 8's CI job
- `xp runner start` on a box without a JDK prints `No android: no JDK ...` with the fix | verify:
  `runner_agent_test`, and by hand
- The pairing dialog and `xp runners pair` print a URL that works from the runner machine once a
  runner URL is set | verify: route, CLI and widget tests
- A runner under its service survives the engine being away for longer than a lease: it stops
  the lost job, reconnects within 60 s of the engine coming back, and the job follows the loss
  rule | verify: `tool/e2e/runner_offline_e2e.sh`
- `xp runners list` and `list_runners` show name, id, status, last seen, capabilities, slots and
  jobs | verify: CLI and MCP tests
- The engine log has one line per runner connect, disconnect and refusal | verify: xpd test
- A project whose origin is on Bitbucket (or `file://`) can be added and runs `dev-build` and
  `test` on a runner, and `prod-release` is refused with a clear reason | verify: the PR 10c e2e
- README says which versions must match | verify: review

## Risks

| Risk | Mitigation |
|---|---|
| The `project` table rebuild corrupts or loses rows in a real database | The backup is taken before migrating. The migration test runs on a populated database, and `foreign_key_check` runs before the commit. Fall back to Q5's alternative if review finds the runner extension too risky. |
| The lease fence stops a job the engine still considers leased (clock or ack delay) | A monotonic clock, measured from the ack's arrival, plus a 15 s margin over the sweep interval. The engine answers `cancel` anyway for a lease it lost. |
| `tailscale serve` syntax and behaviour change between versions | The docs give the version they were checked against. The recipe is plain, and the alternatives are listed. |
| The image is large (the Android SDK is over 1 GB) | One platform and one build-tools version only. Gradle and Flutter caches live in the volume, not the image. |
| Pinned command-line tools go stale | The version and SHA-256 are one line in `install.sh`, bumped like any dependency. |
