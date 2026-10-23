# Install XPath

How to install XPath is in the README ("Releases and installation"): the Mac app with Homebrew or
the DMG, `install.sh` on Linux, the Docker images. This page says which versions have to match once
there is more than one piece.

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
- **Upgrade the engine first.** Runners follow by themselves.
- **Tools a runner uses but XPath does not install** (the Android SDK and the JDK today) are
  checked again whenever the runner starts, after a self-update too. A capability lost that way is
  printed by the runner with its reason and fix, logged by the engine, and shown in Runners in the
  app; `xp runner doctor` says the same on the runner machine.
