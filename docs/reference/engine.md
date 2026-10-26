# Running the engine

How `xpd` runs, as a process and as a service. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## Running the engine

```sh
dart run apps/xpd/bin/xpd.dart token create --name "My Mac" --kind app   # prints the token once
dart run apps/xpd/bin/xpd.dart serve                                      # http://127.0.0.1:7480
```

- `xpd serve [--host 127.0.0.1] [--port 7480] [--data-dir <path>] [--slots <n>]` listens on loopback by default.
  Any other `--host` exposes the engine to the network without encryption, and prints a warning.
  SIGINT and SIGTERM close the server and its WebSocket connections cleanly. `--slots` is how many jobs run at
  once here (see Workflows and the scheduler).
- `xpd token create --name <name> --kind app|cli|mcp|runner` creates a device token and prints it
  once on stdout. Only its SHA-256 is stored. A running engine accepts it at once.
- `xpd secrets import-gh [--data-dir <path>] [--gh <path>]` stores the token of the GitHub CLI in
  the engine's secret store (see Projects and scans).
- Every route except `GET /health` and `GET /version` needs `Authorization: Bearer <token>`.
- `GET /events` is a WebSocket. Each frame carries a `seq`; reconnect with `?after=<last seq>` to
  receive what was missed. [`packages/xp_api/openapi.yaml`](../../packages/xp_api/openapi.yaml)
  documents the API.

The data directory holds the SQLite database, `xpath.db` (ADR 0002). It is
`--data-dir`, else `$XPATH_DATA_DIR`, else `~/Library/Application Support/XPath` on macOS or
`$XDG_DATA_HOME/xpath` (`~/.local/share/xpath`) on Linux.

The database (`packages/xp_adapters/lib/src/sqlite`) is opened with WAL, a busy timeout and foreign
keys, through one connection per process. Its schema is the ordered list in `migrations.dart`,
tracked by `PRAGMA user_version`; each migration runs in a transaction. Before an existing
database is migrated, `xpd` copies it to `xpath.db.bak-v<old version>`. A migration is never
edited once released: add a new one and a golden `test/src/sqlite/snapshots/v<N>.sql`
(`UPDATE_GOLDENS=1 dart test test/src/sqlite/migrations_test.dart` writes it). Events older than
seven days are pruned; their sequence numbers are never reused. Schema version 2 adds the scan
columns of `project`; version 3 adds what the job runner records to `job` and `job_step`; version 4
adds the tool versions of a job; version 5 adds the time and a unique path to `artifact`; version 6 adds
`shorebird_release`, the Flutter version each Shorebird release was built with; version 7 gives `test_run` its
project, app, time and the baseline index; version 8 gives `credential_ref` the result of its last check and
one credential per flavor and kind; version 9 adds `run` and gives `job` its run, stage, name and capabilities;
version 10 gives `approval` its run, job, decision and expiry; version 11 gives `release` its flavor, branch, pull request,
builds and the status in each store; version 12 adds `housekeeping_setting`; version 13 gives `runner` its credential,
what it reported and when it was revoked, and adds `pairing_token`; version 14 replaces `credential_ref` with the
named `credential` and `credential_assignment` (see Credentials, ADR 0013).

Secrets (`packages/xp_secrets`) live on the engine machine behind the `SecretStore` interface of
`xp_engine`; `createSecretStore` picks the implementation for the platform.

- **macOS: Keychain, plus a file for large secrets** (ADR 0004, ADR 0008). Each Keychain operation
  runs one `security -i` and sends one quoted command line on stdin, so a value never appears in
  `ps`. Values are stored as base64 of their bytes, because `security -i` reads one line and prints
  non-ASCII passwords as hex. One command line is limited to 4094 bytes, so the Keychain only takes
  values whose base64 form is at most 2,048 characters (1,536 bytes). A larger secret, such as an
  Android keystore, goes to `secrets.enc` in the data directory (the file described under Linux),
  whose 32-byte key is a random item in the Keychain, created on first use. A key lives in one
  place only: writing a secret that grew or shrank moves it. Services are
  `ly.abdurahman.xpath.credentials` for the secrets and `ly.abdurahman.xpath.master` for the file
  key (ADR 0005). A locked Keychain locks the whole store, large secrets included.
- **Linux: encrypted file.** `secrets.enc` in the data directory, sealed with XChaCha20-Poly1305
  under a 32-byte master key: `$CREDENTIALS_DIRECTORY/xpath-master-key` (systemd
  `LoadCredentialEncrypted=`) if set, else `master.key` in the data directory (mode 0600, created on
  first use, refused if group or world can read it).
- **Text and bytes.** `SecretStore` has `read`/`write` for text (UTF-8) and `readBytes`/`writeBytes`
  for binary values such as keystores; both use the same keys. `read` of a value that is not UTF-8
  is an error.
- **Secrets locked** (D-10). A locked Keychain, a missing or unreadable master key, or a key that does
  not open the file makes the store throw `SecretsLockedException` and set `status` to
  `SecretsStatus.locked` (`statusChanges` announces it). The engine never prompts.
- **Log masking.** `SecretMasker` replaces known secret values with `***` in process output. A
  multi-line secret is masked line by line, overlapping secrets are merged, lines shorter than 6
  characters are ignored, and `MaskingStream` masks a secret split between two chunks.

## Running as a service

The engine and a runner are meant to run all the time, under the service manager of the machine: a LaunchAgent on
macOS, a systemd unit on Linux. The commands only write the file and call `launchctl` or `systemctl` through the
`ProcessRunner` port (`packages/xp_adapters/lib/src/service`).

```sh
xpd install-service [--data-dir <dir>] [--host ...] [--port ...] [--slots ...]   # then: xpd service-status, xpd uninstall-service
xp runner install-service [--slots 4]                                           # then: xp runner service-status, xp runner uninstall-service
```

- **macOS: LaunchAgents** (D-10, ADR 0005). `~/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist` for the engine and
  `ly.abdurahman.xpath.runner.plist` for a runner, loaded with `launchctl bootstrap gui/<uid>` (and `bootout` to
  unload). A LaunchAgent belongs to the login session of the user: the Mac mini of D-10 logs in on its own (an
  auto-login user), and so the engine can reach the login Keychain; a locked Keychain is "secrets locked", the
  engine never prompts. `RunAtLoad` starts it at login; `KeepAlive` with `SuccessfulExit` false starts it again after
  a crash or a restart request, not after a clean exit (a drain, a stop), with a throttle of 10 s. The plist sets a
  `PATH` that finds what launchd's own does not: `/opt/homebrew/bin`, `/usr/local/bin`, `~/.shorebird/bin`,
  `~/.pub-cache/bin`, `~/fvm/default/bin` and the system directories (`--path` replaces it). Output goes to
  `<data dir>/service-logs/xpd.out.log` and `.err.log` (`runner.*` for a runner); launchd does not rotate them.
  **Who owns the label.** The XPath app registers the bundled `xpd` under the same label with `SMAppService`
  (Phase 15); with the app installed the app owns the service and `xpd install-service` is not needed. The command
  is the way to run the engine without the app (a headless Mac mini, a Mac with the CLI only). It reads
  `launchctl print` first and refuses to replace a label that another registration owns, naming it; `--force` takes
  it over. `SMAppService` keeps its own record of the app's agent, apart from launchd: after a `launchctl bootout`
  (older Homebrew casks did that on upgrade) it still reads "enabled" while launchd has no job, `launchctl
  kickstart` finds nothing and `launchctl bootstrap` of the plist fails (`Bootstrap failed: 5`: a `BundleProgram`
  job has to come from `SMAppService`). The app repairs that itself: when the engine on this Mac does not answer, it
  unregisters and registers the agent again from the running bundle (which also fixes a registration that names a
  moved or replaced copy of the app). It tries once on its own; the banner and Settings ▸ About offer **Start
  engine** (see The desktop app).
- **Linux: systemd.** A user unit by default, `~/.config/systemd/user/xpd.service` and `xp-runner.service`, enabled
  and started with `systemctl --user daemon-reload` and `enable --now`; `--system --run-as <user>` writes a system
  unit in `/etc/systemd/system` that runs as that user (run it as root). A user service stops when the user logs out;
  the command says so and names the fix, `sudo loginctl enable-linger <user>`, when the user does not linger.
  `Restart=on-failure` starts it after a crash or a restart request and not after a clean exit; the unit of a runner
  adds `RestartPreventExitStatus=77 73 78` (revoked, replaced, not paired: starting again would not help).
  `KillMode=mixed` sends the stop signal to the main process (the runner drains, the engine shuts down) and kills the
  steps that are left when `TimeoutStopSec` ran out: 30 s for the engine, 600 s for a runner.
- **The master key (D-07).** `--master-key-credential <file>` writes
  `LoadCredentialEncrypted=xpath-master-key:<file>`; `--master-key-credential-plain <file>` writes
  `LoadCredential=xpath-master-key:<file>`. systemd then puts the key in `$CREDENTIALS_DIRECTORY/xpath-master-key`,
  where the secret store reads it, instead of a `master.key` file in the data directory. Make the file with
  `head -c 32 /dev/urandom | systemd-creds encrypt --name=xpath-master-key - xpath-master-key.cred` (see
  <https://systemd.io/CREDENTIALS/>; `--user` for a user unit on systemd 256 or newer). Do this before the first
  secret is stored: a key that changes later does not open the file. A runner has to be paired with the same key
  (`systemd-run --user -p LoadCredentialEncrypted=xpath-master-key:<file> xp runner pair ...`).
- **The runner service runs `<data dir>/current/bin/xp`.** `xp runner install-service` needs a paired runner and an
  `xp` that runs from an installed bundle (`bin/xp` and `lib/`): it copies that bundle to
  `versions/<version>/`, points `current` at it, and writes a service that starts `current/bin/xp runner start`
  with `XP_RUNNER_MANAGED=1`. That is what lets the runner update itself in place (see Runner updates). It must be
  run from the `xp` that is to run.
- **The files that ship.** `tool/release/linux/xpd.service` and `xp-runner.service` are the reference units for the
  packaging of a release (Phase 18a): user units under `%h`. They are what the Dart templates
  (`renderSystemdUnit`) make of `XpdService.reference` and `RunnerServiceDefinition.reference`; a test fails when
  either file differs, and says how to write it again. The commands render from the same templates with the real
  paths.
- **Engine updates** are not done here: the engine updates only when idle and backs up its database before it
  migrates (D-24); that is the app's job (Phase 18c, Sparkle). Runners follow the engine (Runner updates).
- **Tests.** The managers, the templates and the commands are unit tests with a fake `ProcessRunner` and temporary
  folders: no test installs a LaunchAgent or a unit, or calls `launchctl` or `systemctl`.
