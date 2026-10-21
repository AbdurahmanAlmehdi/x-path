# Feedback: setting up a remote runner (2026-10-20)

From pairing a first remote runner: an AWS Ubuntu 24.04 box ("AWS Instance") against an engine
on the owner's Mac (`127.0.0.1:7480`, engine 1.1.2), to build two Flutter apps hosted on
Bitbucket. Pairing worked. The runner was not useful yet, for the reasons below.

## 1. A runner needs its build tools, and nothing installs them (asked for)

`install --runner` installs `xp` and nothing else. A fresh Linux box has no JDK, Android SDK or
Flutter, so the runner offers no `android` or `flutter` capability and the scheduler never gives
it a build job. Nothing says so: `xp runner start` printed only

```
Runner "AWS Instance" connects to http://127.0.0.1:7480.
Nothing was left by an earlier run.
```

The engine prints the same thing at its own start (`xpd runs jobs here with 2 slots and flutter,
android, ios-sign`). The runner does not.

Options, not exclusive:

- **A runner image.** `xpath-runner`, built alongside the engine image, with JDK 17, the Android
  command-line tools (platform-tools, build-tools, a platform, licences accepted), git, ssh and
  `xp`. Flutter can stay out of the image if the runner clones the pinned SDK into its data
  directory, as the engine does under `toolchains/flutter/<version>`. Then one image serves every
  Flutter version, and the volume caches it. Pairing would be
  `docker run ... xpath-runner pair --engine ... --token ...`, then `start`.
- **An installer flag.** `install --runner --with-android` installs the JDK and Android SDK on
  Debian or Ubuntu and points `ANDROID_HOME` at it.
- **Say what is missing, either way.** At start, the runner prints the capabilities it offers and,
  for each one it does not, the reason and the fix ("no `android`: `sdkmanager` not found, set
  ANDROID_HOME or install the command-line tools"). An `xp runner doctor` could print the same
  thing without connecting.

## 2. A runner should stay connected without someone watching it (asked for)

The engine listens on loopback on a laptop, and the runner dials out to it. The only way that
worked was an SSH reverse tunnel opened by hand
(`ssh -R 7480:127.0.0.1:7480 ubuntu@<host>`), so the runner lives only as long as that terminal
and the Mac's awake time. `xp runner install-service` exists, but it does not help while the
engine cannot be reached.

What would close the gap:

- **A supported way to reach the engine.** A documented recipe or built-in command for one of:
  Tailscale (no public port), Cloudflare Tunnel (a TLS hostname), or an autossh reverse tunnel run
  as a LaunchAgent on the engine machine. The README already says a remote runner should use TLS.
  It should name the setup to use.
- **An engine URL for runners.** The pairing dialog printed
  `xp runner pair --engine http://127.0.0.1:7480`, which is the wrong address from any other
  machine. Let the owner set the URL runners use (`--public-url`, or a setting), and have the
  pairing dialog and `xp runners pair` print it.
- **Reconnect with backoff, as a service.** Check that `xp runner start` and the service it
  installs survive the engine going away (Mac asleep, tunnel down) and come back on their own, and
  that leased jobs follow the loss rule. Then document that a runner may be offline for hours.

## 3. Seeing the runners

- `xp runners` has `pair` and `revoke` but no `list`. The CLI cannot tell whether a runner is
  online, what it offers or what it is running. Add `xp runners list` (name, id, online, last
  seen, capabilities, slots, running jobs), and the same as an MCP tool.
- The engine log records nothing when a runner connects, disconnects or is refused. One line for
  each would have answered "did it pair" without the app.

## 4. Bitbucket repositories

`xp projects add <folder>` refuses a clone whose origin is not on GitHub ("The origin of ... is
not on GitHub."), so neither OneAvant app can be added. More than that check would have to
change: ADR 0009 keys the runner's source cache by GitHub repository id and has runners fetch
over `git@github.com`, and `github.createPr` and `github.mergePr` drive the release merge.

A useful first step: accept any git host for workflows with no `github.*` step (dev builds,
`test`). Key the runner cache by the remote URL, and run `ssh -T` against the origin's host.
Pull requests on Bitbucket can come later. Until then, a private GitHub mirror is the
workaround.

## 5. Small things

- `install --runner` ends with the shell-completion hint and nothing about next steps. It should
  print the pairing command and the capability check.
- Engine, CLI and runner each warn that 1.1.3 is out. Say whether a runner and an engine on
  different versions are supported, so the owner knows whether they must upgrade together.
