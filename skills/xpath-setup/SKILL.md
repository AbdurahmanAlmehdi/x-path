---
name: xpath-setup
description: Install and set up XPath, the self-hosted Flutter release tool, and fix it when it does not run. Use when installing the macOS app, the Linux engine or the Docker image, creating device tokens (xpd token create), connecting GitHub, adding store credentials (App Store Connect key, Apple ID, Google Play or Firebase service account, Android keystore, Shorebird, GitHub, Slack), pairing remote runners, finding the data directory and logs, checking health, or troubleshooting the engine. The agent never asks the user to paste a secret into the chat.
license: Apache-2.0
---

# Setting up XPath

XPath is a headless engine (`xpd`) with four clients: the macOS app, the `xp` CLI, `xp mcp` and
remote runners (`xp runner`). The engine owns projects, secrets, jobs and store status, and
listens on `http://127.0.0.1:7480` by default.

## Secrets: the rule

Never ask the user to paste a token, password, key or service account into the chat, and never
put one in a command you run, a file you write or a log. Tell the user **where** to enter it:

- store credentials: the XPath app, **Credentials** ▸ **Add credential…** (the engine checks each
  with the service it is for and stores nothing if the check fails), or `xp credentials add` in
  their own terminal, which asks for a password or token without showing it or reads it from
  standard input (`--token-stdin` and the like), and reads keys from files (`--p8`,
  `--service-account`, `--keystore`), never from an argument;
- the GitHub token: the app, **Settings** ▸ **GitHub**, or `xpd secrets import-gh` in their own
  terminal;
- device tokens and pairing tokens: printed once by a command the user runs in their own
  terminal, and used by them there.

Secrets live on the engine machine: the login Keychain on macOS (services starting with
`ly.abdurahman.xpath`, large ones in `secrets.enc` in the data directory), an encrypted
`secrets.enc` on Linux. No API answer, event or log carries a secret.

## Install

### macOS: the app from a release

Install the notarized app with Homebrew. Homebrew asks to trust a third-party tap once:

```sh
brew trust abdurahmanalmehdi/tap
brew install --cask abdurahmanalmehdi/tap/xpath
```

Add `--adopt` when XPath.app is already in /Applications from the DMG, so Homebrew takes it over.
Update with `brew upgrade --cask xpath`, then restart the engine (below). Without Homebrew, each
GitHub Release of `AbdurahmanAlmehdi/x-path` carries `XPath-<version>.dmg`, signed with Developer ID
and notarized: open it and drag XPath to Applications. Then open XPath and follow the setup below.
Sparkle updates are not available yet.

### macOS: the app built from the repository

For development, or before a release exists, build the app from the repository; it is signed with
the user's Apple Development certificate:

```sh
export PATH="$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH"
tool/release/build_mac.sh --install
```

It builds `xpd` and `xp`, builds `XPath.app` in release mode with both inside
(`Contents/Helpers/xpd`, `Contents/Helpers/xp`), signs it and replaces `/Applications/XPath.app`.
`XPATH_SIGN_IDENTITY` names another signing identity (the default is the repository owner's);
`--reuse-bundles` skips rebuilding the tools when only the app changed. It does not open the app,
register the engine or link `xp`. Needs macOS 13 or later, Xcode, git, and `fvm install` done in
the repository.

Then open XPath. **Set up XPath on this Mac**:

1. **Start engine** registers `ly.abdurahman.xpath.xpd` as a login item (allow it in System
   Settings ▸ General ▸ Login Items if asked).
2. **Link xp** links `xp` into `/usr/local/bin`, else `~/.local/bin`. Check with `xp --version`.
3. **Check the tools**: Xcode, git, fvm, gh, Shorebird.

After installing over a running engine, restart it so it runs the new `xpd`:

```sh
launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd
```

To update, pull the repository and run `tool/release/build_mac.sh --install` again; the engine's
data is kept.

### macOS without the app (headless Mac)

With `xpd` from a release bundle on the `PATH`:

```sh
xpd install-service [--data-dir <dir>] [--host ...] [--port ...] [--slots ...]
xpd service-status
```

It refuses to replace a LaunchAgent label another registration owns (the app's, say) unless
`--force`. With the app installed, the app owns the service and this is not needed.

### Linux

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh                  # engine and CLI, xpd user service
curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner   # a runner machine: pair it afterwards
```

Options: `--version <v>`, `--prefix <dir>` (default `~/.local`), `--archive <path>`, `--runner`,
`--no-service`. The archive's SHA-256 is checked. Running it again updates in place. A user
service stops at logout unless the user lingers: `sudo loginctl enable-linger <user>`.

### Docker

```sh
tool/release/bundles.sh && docker build -t xpath .
docker run -d --name xpath -p 127.0.0.1:7480:7480 -v xpath-data:/data xpath
docker exec xpath xpd token create --name laptop --kind cli
```

The image has no Flutter: builds go to runners. Data lives in the `/data` volume.

## Device tokens

Every client needs a device token, made on the engine machine and printed **once** (only its
SHA-256 is stored; a running engine accepts it at once):

```sh
xpd token create --name "My Mac" --kind cli    # kinds: app, cli, mcp, runner
xpd token create --name "Claude" --kind mcp
xp connect http://127.0.0.1:7480 --token <cli token> --mcp-token <mcp token>
```

With the app, `xpd` is `/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd`; in Docker,
`docker exec xpath xpd ...`. The user runs these and keeps the output; the app makes its own
`app` token during setup, and a runner gets its `runner` credential by pairing.

| Kind | Who uses it | May decide approvals |
|---|---|---|
| `app` | the macOS app | yes (and is the only one that turns a gate off) |
| `cli` | `xp` | yes |
| `mcp` | `xp mcp`, for agents | no (`403`) |
| `runner` | a paired runner; reaches only the runner endpoints | no |

## GitHub

A project is a GitHub repository, so the engine needs a GitHub token before the first project.
Any of:

- the app: **Settings** ▸ **GitHub** ▸ **Import from GitHub CLI** (runs `gh auth token` on the
  engine machine; `gh auth login` first), or paste a token and **Check and save**;
- a terminal on the engine machine:

  ```sh
  xpd secrets import-gh            # prints only "Imported the GitHub token."
  ```

- the API: `PUT /github-token` or `POST /github-token/import` (`app` and `cli` tokens only).

The token needs read access to the repositories and write access (contents and pull requests)
for the release branch, tag and pull request merge. `GET /github-token` shows whether one is
stored, its status and its login.

## Credentials

Credentials are the engine's and have names (ADR 0013): the user adds one once ("Personal Apple
Dev Account") and assigns it to the flavors that use it, of any project. A flavor (an app path and
a flavor name; `.` and `default` for an app without flavors) uses at most one credential of each
kind. The kinds, their fields, where the user gets each and the `xp credentials` commands are in
[references/credentials.md](references/credentials.md).

Each credential shows **Verified**, **Rejected** or **Not checked**, and so does each assignment
(can the credential reach that flavor's app). The engine checks them daily and before each build;
only `rejected` stops a job (at its `credentials` guard). The GitHub token is not a named
credential: the engine has one (**Settings** ▸ **GitHub**).

## Projects

```sh
xp projects add acme/app           # or an absolute folder on the engine machine, or a GitHub URL
xp projects show acme/app          # apps, flavors, ids and the findings of the scan
xp projects scan acme/app
```

The scan is read-only. Findings with severity `error` must be fixed in the repository and scanned
again. The Firebase app ids and App Store Connect app ids are not scanned: they are workflow
inputs (`firebaseAppIds`, `appleAppIds`; skill `xpath-workflows`).

## Runners

A runner is another machine that runs build jobs: a Mac for `ios-sign`, a Linux box for
`android`, `flutter` and `swift-linux`.

```sh
xp runners url https://mac.tailnet.ts.net   # once: the address runners reach the engine at
xp runners pair mac-mini           # on a machine with a cli token: prints the pairing command once
xp runner pair --engine https://mac.tailnet.ts.net --token xpp_...   # on the runner machine
xp runner doctor                   # on the runner: will it get jobs, and why not
xp runner start [--slots 4]        # or keep it running:
xp runner install-service [--slots 4]
xp runner service-status
xp runners revoke mac-mini
```

The user runs the pairing commands: the pairing token (`xpp_...`) is single use, valid for 15
minutes and bound to the runner's name. The runner keeps its credential in the machine's secret
store and dials out to the engine. It fetches the source with its own SSH key, so add the
runner's key as a deploy key on the repository (an access key on Bitbucket). The engine
prints the capabilities it found for itself at start, and the runner prints what it offers and,
for each capability it lacks, why and the fix.

Reaching the engine from another machine (the engine listens on loopback only; the socket carries
signing material, so never `--host 0.0.0.0` over plain http):

1. **Tailscale (recommended).** Tailscale on both machines, MagicDNS and HTTPS Certificates on in
   the admin console, then on the engine's Mac `tailscale serve --bg http://127.0.0.1:7480` and
   `xp runners url https://<mac>.<tailnet>.ts.net` (`tailscale serve status` prints the name).
2. **Cloudflare Tunnel.** `cloudflared tunnel run --url http://127.0.0.1:7480 <tunnel>` with a DNS
   route; Cloudflare Access in front is not supported yet.
3. **SSH reverse tunnel.** `autossh -M 0 -N -R 127.0.0.1:7480:127.0.0.1:7480 user@runner` from the
   Mac; the runner then pairs with `http://127.0.0.1:7480`.

The full recipes: `docs/guide/runners.md#reaching-the-engine` in the XPath repository.

## Health, data and logs

```sh
curl -s http://127.0.0.1:7480/health     # {"status":"ok"} while the engine serves
curl -s http://127.0.0.1:7480/version    # the engine version and API version
xpd service-status                       # a service installed with xpd install-service
xp runner service-status
```

| What | Where |
|---|---|
| Data directory | `--data-dir`, else `$XPATH_DATA_DIR`, else `~/Library/Application Support/XPath` (macOS) or `$XDG_DATA_HOME/xpath` (`~/.local/share/xpath`, Linux) |
| Database | `xpath.db` in the data directory (backed up as `xpath.db.bak-v<N>` before a migration) |
| Engine log under the app | `<data dir>/service-logs/xpd.log` (rotated to `xpd.log.1` past 10 MB at a start) |
| Engine log under `xpd install-service` (macOS) | `<data dir>/service-logs/xpd.out.log` and `xpd.err.log` |
| Job logs | `<data dir>/logs/<jobId>/`, or `xp logs <job>` |
| Runner data | `--data-dir`, else `$XP_RUNNER_DATA_DIR`, else `~/.local/share/xpath/runner` |

When something does not work, see [references/troubleshooting.md](references/troubleshooting.md).

## Remove

In the app: **Settings** ▸ **Remove XPath…** revokes the paired runners, stops and unregisters
the engine and removes the `xp` link; **Also delete engine data** and **Also delete Keychain
items** remove the rest. Repositories are never touched. Only do this when the user asks.

## More

- Running releases once set up: skill `xpath-release`.
- `docs/guide/try-it-locally.md` and the README sections "Running the engine", "Running as a
  service", "Releases and installation", "Credentials" and "Runners" in the XPath repository.
