# ADR 0003: Process groups

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** 0 (decides Phase 7)

## Context

Cancelling a job must stop the whole process tree (`flutter` → `xcodebuild`/`gradle` →
compilers). `Process.kill` signals only the direct child, and Dart cannot run code between
`fork` and `exec`. `ProcessStartMode.detached*` calls `setsid` but then gives no exit code, so
it is unusable for steps.

## Decision

Start every step process through a tiny `perl` trampoline that makes the child a process-group
leader and then execs the real command:

```text
perl -e 'setpgrp(0,0); exec @ARGV or die "exec: $!"' -- <executable> <args...>
```

- The returned PID is the process-group ID.
- Cancel sends `SIGTERM` to the group with `Process.killPid(-pgid, ProcessSignal.sigterm)`,
  waits 10 s, then sends `SIGKILL` to the group.
- `perl` ships with macOS and is `perl-base` (Essential) on Debian/Ubuntu, including
  `debian:bookworm-slim`. The engine checks for it at start and reports a missing `perl` as a
  toolchain error.
- On start, the engine reaps orphans: groups recorded for jobs left `running` are signalled the
  same way before those jobs are marked `interrupted` (D-18).

## Proof

Spike program: start `sh -c 'sleep 300 & echo gc=$!; wait'` through the trampoline, read the
grandchild PID, send SIGTERM to `-pid`, then probe the grandchild with `kill -0`. Control: the
same command without the trampoline, cancelled with `Process.kill`.

```sh
dart run bin/main.dart                     # macOS 26
# leader=81530 pgid=81530 grandchild=81531
# killPid(-pgid) returned true
# leader exit=-15 grandchild alive=false
# control grandchild alive=true

dart build cli --target-os linux --target-arch arm64 -o outl
docker run --rm -v $PWD/outl/bundle:/b debian:bookworm-slim /b/bin/main   # Linux, AOT
# leader=193 pgid=193 grandchild=195
# killPid(-pgid) returned true
# leader exit=-15 grandchild alive=false
# control grandchild alive=true
```

## Consequences

- No FFI for process control.
- `perl` becomes a documented runtime requirement for the engine and runners (Docker image
  included).
