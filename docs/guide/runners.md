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

## When the engine is away

A runner may be cut off from the engine for hours: the engine's Mac sleeps, the tunnel drops, the
network changes. Nothing needs restarting.

- **The runner keeps trying.** It reconnects with a growing delay, at most 60 seconds between
  attempts, and comes back within about a minute of the engine. Its log stays short: one line when
  the connection is lost, one for the first failed attempt, then one every 10 minutes ("The engine
  has been unreachable for 2 h 10 min; still trying every 60 s"), and one when it is back
  ("Connected again after 3 h 12 min").
- **A job it holds is stopped once its lease runs out.** A lease lasts 90 seconds after the last
  heartbeat the engine acknowledged. When 90 seconds and 15 more have passed without one, the
  engine has given the job up, so the runner stops it as a cancel would: its processes end, its
  secrets are wiped, and nothing more is reported. The runner says `Lost the lease of job <id>
  while the engine was unreachable; stopped it.`
- **The engine decides what happens to the job.** It is queued again, or, when the step that was
  running has a side effect (an upload, a push, a Shorebird release), it waits for you to resume it
  and is never repeated by itself.

So keep the engine's Mac awake while runners have work: a Mac that sleeps in the middle of a build
loses the build. A Mac mini that never sleeps is the setup the plan assumes (D-10); a laptop engine
is your call.

## Reaching the engine

The engine listens on `127.0.0.1:7480`, so only its own machine reaches it. A runner on another
machine needs an address that leads there.
