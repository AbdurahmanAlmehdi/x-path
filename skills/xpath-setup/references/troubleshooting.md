# Troubleshooting

Start with these, in order:

```sh
curl -s http://127.0.0.1:7480/health       # does the engine answer?
curl -s http://127.0.0.1:7480/version      # which engine and API version?
xp projects list                           # do the URL and the cli token work? (exit codes below)
tail -n 100 ~/Library/Application\ Support/XPath/service-logs/xpd.log   # the engine under the app
```

## The engine does not answer

- **Under the app (macOS).** Open XPath: when the engine on this Mac does not answer, the app
  tries once to start it again on its own (it registers the login item again and reconnects with
  the token it has). If that fails, the banner says "The engine on this Mac isn't running." Press
  **Start engine** there, or in **Settings** ▸ **About** next to **Engine on this Mac** (Running /
  Not running). Do not remove This Mac and set it up again: the engine's data and the app's token
  are kept. The banner says why a start failed: allow XPath in System Settings ▸ General ▸ Login
  Items (**Open Login Items…**) and press **Start engine** again; open the copy in
  `/Applications`; or read `service-logs/xpd.log` in the data directory.
- **`launchctl print gui/$(id -u)/ly.abdurahman.xpath.xpd` says "Could not find service"** while
  the app's login item reads enabled (a `launchctl bootout`, for example by an old Homebrew
  upgrade): `launchctl kickstart` and `launchctl bootstrap` cannot bring it back (`Bootstrap failed:
  5`, the job belongs to `SMAppService`). Open XPath, or press **Start engine**.
- **After an install over a running engine** the old `xpd` keeps running until it restarts:

  ```sh
  launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd
  ```

- **A Debug build opened instead of the installed app**: they share the bundle id, and a Debug
  build's LaunchAgent points at a bundle without `xpd` (launchd `EX_CONFIG`).
  `tool/release/build_mac.sh --install` makes LaunchServices forget the build-folder copies;
  open `/Applications/XPath.app`.
- **Under `xpd install-service`**: `xpd service-status`; the output is in
  `service-logs/xpd.out.log` and `xpd.err.log` (macOS). On Linux a user service stops when the
  user logs out unless `sudo loginctl enable-linger <user>`.
- **`xpd serve` refuses to start without `perl`** (every step process starts through a `perl`
  trampoline). It ships with macOS and Debian/Ubuntu.
- **`XPD_PLAY_TARGET_SDK`** set to anything but a whole number from 21 to 99 stops the engine at
  start.
- **Another port or host.** `xpd serve` listens on `127.0.0.1:7480` unless `--host`/`--port` say
  otherwise; any other host is unencrypted and the engine warns.

## Secrets locked

`503 secrets_locked` (exit 69 from `xp`, a banner in the app, a notification): the engine cannot
open its secret store, and it never prompts.

- macOS: the engine runs in the user's login session and reads the login Keychain. A locked
  Keychain locks everything, large secrets included. A Mac that should run releases unattended
  logs in on its own (an auto-login user).
- Linux: `master.key` (0600) in the data directory, or `$CREDENTIALS_DIRECTORY/xpath-master-key`
  from a systemd credential, is missing, unreadable, readable by group or others, or not the key
  the file was sealed with. A key that changes after the first secret was stored does not open
  the file.

## Tokens and connecting

| Symptom | Cause | Fix |
|---|---|---|
| exit 78, "not connected" | no saved engine URL or token | `xp connect <url> --token <cli token>` (and `--mcp-token` for `xp mcp`) |
| exit 77, "The engine rejected the cli token" | token unknown or revoked | the user makes a new one with `xpd token create --name <name> --kind cli` |
| `403` for an action | the token kind may not do it (an `mcp` token never approves) | the owner does it in the app or with their `cli` token |
| "speaks API v..." | `xp` and the engine are different versions | install the `xp` that matches the engine |
| `xp --version` not found | `xp` was not linked | the app's onboarding, or **Settings** ▸ **Command line tool** ▸ **Link xp**; then open a new terminal |

`XP_ENGINE_URL`, `XP_TOKEN` and `XP_MCP_TOKEN` override the saved values, which helps when the
Keychain should not be touched (CI, scripts).

## GitHub

- Adding a project answers `502` without a GitHub token. Connect one (Settings ▸ GitHub, or
  `xpd secrets import-gh`).
- `xpd secrets import-gh` fails when `gh` is missing, fails or is not logged in (`gh auth login`),
  or when the secrets are locked. It looks for `gh` on `PATH`, then `/opt/homebrew/bin/gh` and
  `/usr/local/bin/gh`; `--gh <path>` names it.
- `422 credential_rejected` on save: GitHub refused the token. Nothing was stored.
- A merge that fails with GitHub's `409`: the release branch moved since the tag; XPath merges
  only the tagged commit.

## Tools on the engine machine

The engine finds Flutter, fvm, Shorebird and Homebrew tools in their usual folders even under
launchd's short `PATH` (`~/.shorebird/bin`, `~/.pub-cache/bin`, `~/fvm/default/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`). It never installs or updates Shorebird, gh or Xcode.

- **Flutter**: pinned per app by `.fvmrc`. fvm installs a missing version; without fvm the engine
  clones the exact version into `<data dir>/toolchains/flutter/<version>`. A pin that is missing
  or not exact (without fvm) fails the build with a fix.
- **Xcode**: `ios-sign` needs `xcode-select -p` and `xcodebuild` to find a full Xcode (the
  Command Line Tools alone do not count).
- **Android SDK**: `android` needs `ANDROID_HOME`, `ANDROID_SDK_ROOT` or Android Studio's default
  location. Flutter ships no Android release compiler for Linux on ARM.
- A job that waits with "No runner can do ios-sign." (or `android`) has nowhere to run: add the
  tool to the engine machine or pair a runner that has it. An iOS job that says "It needs
  ios-sign: ..." could have run on a Linux `ios-linux` runner but for the reasons it gives (a
  flavor, CocoaPods plugins, no Apple Distribution identity for the flavor, ...); the scan's
  `ios_needs_mac` finding lists the project's.
- **omarchy-apple-dev** (`ios-linux`, Linux only): `xp runner doctor` lists each missing piece with
  its fix: the checkout at the pinned commit, Swift, the darwin SDK bundle, rcodesign, the LLVM
  tools and the pymobile3 python. The first iOS job of a Flutter version runs `flutter/setup.sh`
  (about 7 GB, a few minutes) in `toolchains/flutter-ios-linux/<version>` of the runner.

## Runners

- `xp runner pair` exchanges a pairing token that is single use and valid for 15 minutes; an
  expired or used one answers `401`. Make a new one with `xp runners pair <name>`. Pairing again
  in a paired data directory needs `--force`.
- Exit codes of `xp runner start`: 0 drained or done, 77 revoked or credential refused, 73
  replaced by another connection of the same runner, 78 not paired, 69 `perl` missing, 75
  switched to another version (its service manager starts it again).
- Checkout failures say what to do: add the runner's SSH key as a deploy key on the repository
  (an access key on Bitbucket), remove a host key that changed (`ssh-keygen -R <host>`), or push
  the commit. A host key the runner has not seen is recorded on the first fetch.
- A runner updates itself to the engine's version between jobs. "This engine has no runner bundle
  for linux-arm64" means the engine has no `xp.tar.gz` for that machine; put it in
  `<data dir>/bundles/<engine version>/<os>-<arch>/xp.tar.gz`.
- A runner that vanished mid-job: after its 90 second lease, a job with a side effect left is
  `waiting_for_resume` (resume it by hand); one without is queued again.

## Disk

```sh
xp storage report
xp storage free                    # a dry run: what would be freed
```

Deleting (`xp storage free --apply`) and retention (`xp storage retention --keep n --log-days n`)
are the owner's decisions; suggest them, do not run them unasked.
