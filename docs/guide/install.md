# Install XPath

XPath is an engine, `xpd`, and the clients that talk to it: the Mac app, the `xp` CLI, `xp mcp` and
runners. On a Mac you install the app, which carries the engine and `xp`. On Linux you install the
engine and the CLI with one command, or run the Docker image. This page has the steps and says which
versions have to match; [the installation reference](../reference/installation.md) has every option
and how releases are built.

## Install the Mac app

Install the notarized app with Homebrew. Homebrew asks you to trust the third-party tap once:

```sh
brew trust abdurahmanalmehdi/tap
brew install --cask abdurahmanalmehdi/tap/xpath
```

Add `--adopt` when XPath.app is already in `/Applications` from the DMG, so Homebrew takes it over.
Without Homebrew, download `XPath-<version>.dmg` from the
[latest release](https://github.com/AbdurahmanAlmehdi/x-path/releases/latest), open it and drag
XPath to Applications.

Open XPath. The first window, **Set up XPath on this Mac**, has three steps:

1. **Start engine** registers the engine (`ly.abdurahman.xpath.xpd`) as a login item, so it runs now
   and at every login. If asked, allow XPath in System Settings ▸ General ▸ Login Items.
2. **Link xp** links `xp` into `/usr/local/bin`, or `~/.local/bin` when that is not writable. Open a
   new terminal and check it with `xp --version`.
3. **Check the tools** looks for Xcode, git, fvm, gh and Shorebird.

The engine listens on `http://127.0.0.1:7480`. `curl -s http://127.0.0.1:7480/health` answers
`{"status":"ok"}` while it serves. The app owns the engine's service: you need nothing else.

## Install on Linux

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh
```

It downloads the latest release from GitHub Releases, refuses it when the SHA-256 does not match,
and installs the engine and the CLI in `~/.local/lib/xpath`, with `xpd` and `xp` linked in
`~/.local/bin`. With a systemd user session it then installs and starts the `xpd` user service. Pass
options after `sh -s --`:

| Option | What it does |
|---|---|
| `--version <v>` | Installs that release. GitHub's latest release is never a pre-release, so a pre-release needs it. |
| `--prefix <dir>` | Installs under another folder than `~/.local`. |
| `--archive <path>` | Installs a local archive or unpacked release folder. |
| `--no-service` | Installs the files only. |
| `--runner` | Sets up a runner machine and ends with the pairing and service commands. |
| `--with-android` | With `--runner`, on Debian or Ubuntu: also installs a JDK 17, git and the Android SDK. |

A runner machine is one command; [Runners](runners.md#set-up-a-linux-runner) has the rest:

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner --with-android
```

A user service stops when you log out. Keep it running with `sudo loginctl enable-linger <user>`.

## Run the Docker image

```sh
docker run -d --name xpath -p 127.0.0.1:7480:7480 -v xpath-data:/data \
  ghcr.io/abdurahmanalmehdi/xpath:<version>
docker exec xpath xpd token create --name laptop --kind cli
```

- The image is built for `linux/amd64` and `linux/arm64`. The tag `latest` is the newest release
  that is not a pre-release.
- The engine keeps its data, the database and `master.key` included, in the volume `/data`.
- The image has no `unzip`, which the Flutter download needs, so it builds nothing itself: builds go
  to runners. `ghcr.io/abdurahmanalmehdi/xpath-runner` is a runner that builds Android and Flutter
  apps; see [The runner image](runners.md#the-runner-image).

## Run the engine as a service

With the app installed, the app runs the engine. Without it (a headless Mac, or Linux installed with
`--no-service`), let the service manager keep `xpd` running:

```sh
xpd install-service [--data-dir <dir>] [--host ...] [--port ...] [--slots <n>]
xpd service-status
xpd uninstall-service
```

- **macOS:** a LaunchAgent, `~/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist`. It refuses to
  replace the app's registration unless you pass `--force`.
- **Linux:** a user unit, `~/.config/systemd/user/xpd.service`. `--system --run-as <user>`, run as
  root, writes a system unit in `/etc/systemd/system` instead.
- The service starts again after a crash, not after a clean stop.
- On Linux the engine seals its secrets with a `master.key` in its data directory. To keep the key in
  a systemd credential instead, pass `--master-key-credential <file>` before the first secret is
  stored. [Running as a service](../reference/engine.md#running-as-a-service) has the details.

## Connect the CLI

`xp` needs a device token of kind `cli`. In the app, **Settings** ▸ **CLI and agents** ▸ **New xp
token** shows the command to run. Or, on the engine machine:

```sh
xpd token create --name "My Mac" --kind cli
xp connect http://127.0.0.1:7480   # asks for the token
xp status
```

The token is printed once. With the app, `xpd` is
`/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd`; in Docker, run `docker exec xpath xpd ...`.
`xp doctor` checks that `xp` reaches the engine and what the engine finds on its machine.

## Find the data directory and logs

| What | Where |
|---|---|
| Data directory | `~/Library/Application Support/XPath` on macOS, `~/.local/share/xpath` (`$XDG_DATA_HOME/xpath`) on Linux, `/data` in Docker. `--data-dir` or `$XPATH_DATA_DIR` sets another. |
| Engine log under the app | `<data dir>/service-logs/xpd.log`, moved to `xpd.log.1` past 10 MB at a start |
| Engine log under `xpd install-service` on macOS | `<data dir>/service-logs/xpd.out.log` and `xpd.err.log` |
| Job logs | `<data dir>/logs/<job id>/`, or `xp logs <job>` |
| Secrets | macOS: the login Keychain, services starting with `ly.abdurahman.xpath`, large ones in `secrets.enc`. Linux: `secrets.enc` in the data directory. |
| Runner data | `~/.local/share/xpath/runner` on the runner, or `--data-dir`, or `$XP_RUNNER_DATA_DIR` |

[Storage](storage.md) says what else is in the data directory and how to free space.

## Update XPath

- **Mac app:** `brew upgrade --cask xpath` (or a newer DMG), then restart the engine so it runs the
  new `xpd`: `launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd`. If that cannot find the
  service, open XPath: it starts the engine again.
- **Linux:** run the install command again. It updates in place and restarts the service.
- **Docker:** start a container of the new tag with the same `/data` volume.

Before the engine migrates its database it copies it to `xpath.db.bak-v<old version>`. Update the
engine first; runners follow it by themselves.

## Which versions work together

- **A runner always runs its engine's version.** It updates itself between jobs: when the engine's
  welcome names another version, the runner takes no new job, lets the running ones finish,
  downloads the engine's own `xp` bundle and starts again as it. So a runner and an engine on
  different versions are supported only for the minutes the update takes. `xp runner start` says
  so: `The engine runs 1.1.3; this runner (1.1.2) updates to it between jobs`. A runner never
  checks GitHub for a newer release; it follows its engine.
- **The app, the CLI and `xp mcp` need an engine with the same API version.** Every 1.x release
  serves API 1 (`xpd --version` prints it), so they need not be upgraded together: an app of 1.4
  works with an engine of 1.2, and the other way round.
- **One exception: projects that are not on GitHub** (ADR 0015). They have no GitHub repository
  id, and an app, CLI or `xp mcp` from before they were added cannot read them: the projects list
  fails to load while such a project exists. Upgrade those along with the engine before you add a
  project from Bitbucket, another SSH host or a `file://` remote.
- **Upgrade the engine first.** Runners follow by themselves.
- **Tools a runner uses but XPath does not install** (the Android SDK and the JDK today) are
  checked again whenever the runner starts, after a self-update too. A capability lost that way is
  printed by the runner with its reason and fix, logged by the engine, and shown in Runners in the
  app; `xp runner doctor` says the same on the runner machine.
