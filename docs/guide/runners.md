# Runners

A runner is another machine that runs jobs for your engine: a Linux box for Android and Flutter
builds, another Mac for iOS signing. It dials out to the engine, so nothing on the runner needs an
open port. This guide is the setup from the owner's side; the README's Runners section has the
protocol and the details.

## Pair a runner

1. Tell the engine the address runners reach it at, the **runner URL**:

   ```sh
   xp runners url https://mac.tailnet.ts.net
   ```

   The app has the same field in Settings, Runners. Every pairing command carries it. Without one,
   the pairing command names the address the CLI or the app reaches the engine at, which is
   usually `http://127.0.0.1:7480`: that address only works on the engine's own machine.
   [Reaching the engine](#reaching-the-engine) says how to get an address another machine can use.

2. Make a pairing token on the engine (or with Pair runner in the app):

   ```sh
   xp runners pair aws-builder
   ```

   It prints the whole command for the runner, which works once, within 15 minutes:

   ```text
   On the runner machine, within 15 minutes:
     xp runner pair --engine https://mac.tailnet.ts.net --token xpp_...
   ```

3. On the runner, run that command, then `xp runner start`, or `xp runner install-service` to keep
   it running.

Runners paired already keep the address they were paired with (it is in their `runner.json`). After
you change the runner URL, for example when you move from an SSH tunnel to Tailscale, pair each
runner again: `xp runners pair <name>` on the engine, then the printed `xp runner pair` on the
runner, which replaces its old credential.

## Reaching the engine

The engine listens on `127.0.0.1:7480`, so only its own machine reaches it. A runner on another
machine needs an address that leads there.
