# Troubleshooting

This page lists the problems you are most likely to meet, what causes each and how to fix it.
Start with the first checks: they tell you whether the engine runs, whether `xp` reaches it and
what the engine finds wrong with its own machine.

## First checks

```sh
xp status    # the engine xp is connected to, its version, the token xp holds, locked secrets
xp doctor    # whether xp reaches the engine, then what the engine finds about its machine
```

`xp status` names the engine URL, the engine and API version, the name and kind of the token, and
whether the secrets are locked. `xp doctor` checks the saved config, that the engine answers and
that it accepts the token. Then it prints the engine's own checks (`GET /doctor`): what the
engine's machine can build and the fix for each missing tool, the secrets, the GitHub token, the
credentials refused at their last check, and SSH to each git host that is not GitHub. It exits
with 1 when something is missing. A tool the engine's machine lacks is listed as skipped, not
missing: a job that needs it goes to a runner that has it. Both take `--json`.

Two routes need no token, so they work even when the token does not:

```sh
curl -s http://127.0.0.1:7480/health     # {"status":"ok"} while the engine serves
curl -s http://127.0.0.1:7480/version    # the engine version and API version
```

## The engine does not answer

`xp` exits with 69, `xp mcp` returns `unreachable`, or `xp doctor` says "the engine does not
answer".

- **Under the app.** The app tries once to start the engine again on its own. If that fails, the
  banner says "The engine on this Mac isn't running." Press **Start engine** there, or in
  **Settings** ▸ **About**. Do not remove This Mac and set it up again: the engine's data and the
  app's token are kept. If it still does not start, the banner says why: allow XPath in System
  Settings ▸ General ▸ Login Items (**Open Login Items…**), open the copy in `/Applications`, or
  read the engine log.
- **After an update over a running engine**, the old `xpd` keeps running until it restarts:

  ```sh
  launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd
  ```

  If `launchctl` says it cannot find the service, open XPath or press **Start engine**.
- **Under `xpd install-service`**, run `xpd service-status`. On Linux a user service stops when
  you log out unless you run `sudo loginctl enable-linger <user>`.
- **`xpd serve` refuses to start without `perl`.** It ships with macOS and Debian or Ubuntu.
- **`XPD_PLAY_TARGET_SDK`** set to anything but a whole number from 21 to 99 stops the engine at
  start.
- **Another address.** The engine listens on `127.0.0.1:7480` unless `--host` or `--port` say
  otherwise. `XP_ENGINE_URL` overrides the URL `xp` saved.

## xp is not connected

`xp` exits with 78 and says it is not connected: it has no saved engine URL or token. Connect it
with a `cli` token from **Settings** ▸ **CLI and agents** in the app, or from
`xpd token create --name <name> --kind cli`:

```sh
xp connect http://127.0.0.1:7480   # asks for the CLI token
```

- **"speaks API v..."**: `xp` and the engine are different versions. Install the `xp` that
  matches the engine.
- **`xp` is not found**: link it in the app (**Settings** ▸ **Command line tool** ▸ **Link xp**),
  then open a new terminal.
- **Start over**: `xp disconnect` forgets the saved engine and tokens. The tokens keep working on
  the engine, and `XP_ENGINE_URL`, `XP_TOKEN` and `XP_MCP_TOKEN` still apply.

## The token is rejected

`401 unauthorized`, exit 77 with "The engine rejected the cli token", or "The engine rejected the
MCP token" from `xp mcp`: the token is unknown or was revoked. Make a new one in the app or with
`xpd token create`, then connect again (`xp connect --token <token>` or `--mcp-token <token>`).

A runner's pairing token works once, within 15 minutes; a used or expired one also answers `401`.
Make a new one with `xp runners pair <name>`.

## The token may not do this

`403 forbidden`, exit 77: the token is valid, but its kind may not do this. An `mcp` token never
approves or denies, changes a gate, marks a store status, abandons a release, frees storage,
changes the GitHub token or pairs a runner. Only the app turns a gate off. Do it yourself in the
app or with `xp` and a `cli` token. [Use XPath from an agent](mcp.md) explains what an agent can do.

## Secrets are locked

`503 secrets_locked`, exit 69, a banner in the app, or `secrets locked` in `xp status`: the engine
cannot open its secret store. It never prompts, and nothing can be built or uploaded until the
store opens.

- **macOS.** The engine runs in your login session and reads the login Keychain. A locked Keychain
  locks every secret, large ones included. Log in to the Mac. A Mac that runs releases unattended
  should log in on its own (an auto-login user).
- **Linux.** `master.key` in the data directory, or `$CREDENTIALS_DIRECTORY/xpath-master-key` from
  a systemd credential, is missing, unreadable, readable by group or others (it must be 0600), or
  not the key the store was sealed with. A key that changes after the first secret was stored
  does not open the store.

## A credential check fails

`422 credential_rejected` when you save: the service it is for refused it (expired, revoked, a
wrong password, a missing role). Nothing was stored and the old credential stays. The message says
what to fix.

A saved credential shows **Rejected** when a later check fails. The engine checks every day and
before each build, and a job stops at its `credentials` guard only for a rejected one. **Check
now** in the app or `xp credentials verify <credential>` checks again, and `xp doctor` lists the
refused ones. Replace a rejected credential in the app (**Credentials**) or with
`xp credentials replace`. [Credentials](credentials.md) has where to get each one.

The engine also needs a GitHub token before it can add a project: without one, adding a project
answers `502`. Connect one in **Settings** ▸ **GitHub** or with `xpd secrets import-gh`.

## A job waits for a runner

A queued job that says `No runner can do ios-sign.` (or `android`, `flutter`, `swift-linux`) has
nowhere to run: no connected machine offers that capability.

- `xp doctor` shows what the engine's own machine offers and, for each missing tool, the fix.
- `xp runners list` shows each runner, what it offers and what it runs. On a runner,
  `xp runner doctor` says what it offers and why not the rest.
- Add the tool to the engine's machine (Xcode for `ios-sign`, the Android SDK for `android`) or
  [pair a runner](runners.md#pair-a-runner) that has it.

`Waiting for run <id> to finish` is not a runner problem: another production run of the project
holds the project lock, and the job takes its turn.

## A runner is offline or lost

A runner is **offline** when it has no connection, and **lost** when it went offline while it
still held jobs. It reconnects on its own within about a minute of the engine coming back
([When the engine is away](runners.md#when-the-engine-is-away)).

- 90 seconds after a lost runner's last heartbeat, the engine gives up its jobs. A job without a
  side effect left is queued again. A job whose step uploads, pushes or tags waits as
  `waiting_for_resume`: resume it with `xp jobs resume <job>`, which first asks the step whether
  its work already exists.
- `xp runner start` exits with 77 when the runner was revoked or its credential refused, 73 when
  another connection of the same runner replaced it, and 78 when it is not paired. Pair it again;
  in a data directory that is already paired, add `--force`.
- Checkout failures say what to do: add the runner's SSH key as a deploy key of the repository
  (an access key on Bitbucket), remove a host key that changed (`ssh-keygen -R <host>`), or push
  the commit.

## A store upload fails

The job log names the store's error. Do not dispatch again to retry an upload; resume the job so
the step checks first whether the store has the build.

- **App Store Connect.** `ITMS-90186` or `ITMS-90062`: bump the version. `ITMS-90189`: the build
  number was used; this one needs a new dispatch, which takes a new build number. An
  authentication error: replace the App Store Connect key or the app-specific password. An upload
  Apple neither accepts nor refuses within 30 minutes fails; resume it later.
- **Google Play.** "Play has a review in progress": XPath never cancels a review. Wait for it to
  end.
- **Firebase.** The version in the binary is not the job's version.
- **`build.ios` needs macOS (ios-sign)**: the job ran where there is no Xcode.

## A workflow is invalid

`422 workflow_invalid`, exit 65: the document has issues, each with its line and column, or a
dispatch cannot be planned (an unknown flavor, a value a step refuses, or a missing credential
such as `The flavor "dev" has no firebase_sa credential saved`). Nothing was stored or started.

```sh
xp workflows validate <project> -f workflow.yaml    # prints line:column: message
```

Fix the document, or the dispatch arguments, and try again. A missing credential is assigned in
the app or with `xp credentials assign`. [Workflows](workflows.md) covers the document.

## Where the logs are

| What | Where |
|---|---|
| The engine under the app | `service-logs/xpd.log` in the data directory |
| The engine under `xpd install-service` (macOS) | `service-logs/xpd.out.log` and `xpd.err.log` in the data directory |
| A job | `xp logs <job>`, or `logs/<job id>/` in the data directory |
| The data directory | `--data-dir`, else `$XPATH_DATA_DIR`, else `~/Library/Application Support/XPath` (macOS) or `$XDG_DATA_HOME/xpath`, `~/.local/share/xpath` by default (Linux) |

```sh
tail -n 100 ~/Library/Application\ Support/XPath/service-logs/xpd.log
```

Job logs are masked: secrets read `***`. The reference is in
[Running the engine](../reference/engine.md).
