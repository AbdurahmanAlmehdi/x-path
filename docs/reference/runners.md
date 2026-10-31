# Runners

Pairing, the connection, capabilities, leases, what never goes to a runner, the agent and its updates. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## Runners

A runner is a machine that runs jobs for the engine (D-08, D-19): another Mac for `ios-sign`, a Linux box for
`android`, `flutter` and `swift-linux`. The engine is also a runner (the local one). Phase 14a is the engine
side: the protocol, the leases, the probe and the endpoints. The runner agent, `xp runner`, is Phase 14b
(see The runner agent below).

### Pairing

Setting up a runner step by step: [docs/guide/runners.md](../guide/runners.md). How a runner on
another machine reaches the engine (Tailscale, Cloudflare Tunnel, an SSH tunnel):
[Reaching the engine](../guide/runners.md#reaching-the-engine).

```sh
xp runners url https://mac.tailnet.ts.net   # the address runners reach the engine at; pairing commands carry it
xp runners pair mac-mini        # on any machine with a cli token: prints the pairing command, once
# on the runner machine: xp runner pair --engine <url> --token <pairing token> exchanges it for the credential
xp runners revoke mac-mini      # kills the credential, the connection and the leases
```

- **Pairing token** (`POST /runners/pairing-tokens`, `app` and `cli` tokens only: a paired runner receives signing
  material, so an `mcp` token must not be able to pair one). `xpp_` and 43 URL-safe characters, **single use**, valid
  for **15 minutes**, bound to the name of the runner. Only its SHA-256 is stored. The names of runners are unique,
  revoked runners keep theirs.
- **Exchange** (`POST /runners/pair`, no bearer token: the pairing token is the proof). It makes the runner and its
  credential, a device token of kind `runner` (D-06), which is shown once; only its hash is stored. Two exchanges of one
  token make one runner (a compare-and-set on `used_at`). Unknown, expired and used tokens answer `401`.
- **Revoke** (`POST /runners/{id}/revoke`, `app` and `cli`): the credential stops authenticating, the connection closes
  (code 4003) and every lease the runner holds ends **at once**, each job by the loss rule below. Revoking again
  changes nothing. `GET /runners` lists the runners with their status (`offline`, `online`, `draining`, `revoked`), the
  capabilities the probe found, the slots and the jobs they hold; `app`, `cli` and `mcp` tokens can read it.
- **A runner token is scoped to the runner endpoints** (ADR 0011): `GET /runners/connect`,
  `GET /runners/bundle` (the bundle a runner updates itself with, see Runner updates) and
  `PUT /runners/jobs/{id}/artifacts/{name}` and nothing else. Every other route answers a `runner` token
  `403 forbidden` with a message that names the route (`runnerScopeMiddleware`, in front of the router, so a
  route added later is closed to runner tokens until someone opens it). A runner holds signing material for
  the jobs it leases, so a stolen credential must not be able to read projects, jobs, credentials or approvals.

### The connection

A runner dials out (nothing connects to it): `GET /runners/connect`, a WebSocket with the credential as the bearer
token (other kinds of token answer `403`; browsers are refused). Every text frame is a JSON object with a `type`.
`RunnerFrame` (runner to engine) and `EngineFrame` (engine to runner) are sealed types in `packages/xp_api`
(`runner_protocol.dart`), and `openapi.yaml` describes each frame as a schema; contract tests check the frames the
real engine sends against them.

| Runner sends | Engine sends | What |
|---|---|---|
| | `welcome` | the runner's id, the heartbeat interval (30 s) and the lease length (90 s) |
| `hello` | `probe` | version, os, arch, cores, optional `maxJobs`, the leases it still holds; then the probe commands |
| `probe_result` | | the results; the engine derives the capabilities and the runner is online |
| | `lease_offer` | a job: its steps with their state, the capabilities, the repository (SSH URL and GitHub id) and the exact commit, the keys of the secrets it may ask for |
| `lease_accept`, `lease_reject` | | take or refuse the offer (`draining`, `busy`) |
| `heartbeat` | `heartbeat_ack` | renews the leases it lists; the ack says until when |
| `log_chunk` | `chunk_ack` | numbered output lines; `stored`, `duplicate` or `gap`, and the chunk wanted next |
| `step_state` | | where a step is; idempotent |
| `job_done` | `done_ack` | ends the job; the ack says the state the engine recorded |
| `secret_request` | `secret_value`, `secret_denied` | signing material of the leased job (D-09) |
| `drain` | | asks for no more jobs, or starts again |
| | `cancel` | stop this job: the lease is gone, the job was cancelled, or the engine does not know the lease |
| | `fault` | a frame the engine could not use |

A second connection of the same runner replaces the first (close code 4001). The engine closes with 4008 when a
runner sent nothing for a whole lease or did not answer the probe in 60 s, and with 4400 for something that is not a
frame (also: the first frame must be `hello`). A frame the engine cannot read is answered with a `fault` and
ignored; a runner ignores a type it does not know. The engine pings every 30 s.

### Capability probing (D-19)

The engine does not trust what a runner says about itself; the `hello` carries no capabilities. After every `hello` it
sends fixed commands (`RunnerProbe`) and derives the capabilities from what they print, with the same rules as
`LocalCapabilities` for the engine's own machine: `flutter` when `git --version` runs, `android` when a folder with
`platform-tools`, `cmdline-tools` or `build-tools` is `ANDROID_HOME`, `ANDROID_SDK_ROOT` or a default place of Android
Studio, `ios-sign` on macOS (`uname -s`) when `xcode-select -p` and `xcodebuild -version` find an Xcode, `swift-linux` on
Linux when `swift --version` runs, and `ios-linux` on a Linux runner started with `XP_IOS_LINUX_DIR`: the runner adds
the commands of that omarchy-apple-dev checkout and sends the folder (`iosLinuxDir`), and the engine checks its
commit against the pin of this release, Swift, the darwin SDK bundle, `rcodesign`, the llvm tools and
the pymobile3 python, each missing piece with its fix (`xp runner doctor` runs the same checks, and
`install-service` writes the variable into the service). A runner without the variable never lists `ios-linux` as
missing. Nothing touches a keychain, and `xcodebuild` and `swift` are not even started where
macOS would answer with a dialog (`requires` and `onlyOn` in the command). A runner gets jobs only after it answered; a
change of capabilities since the last connection is recorded as a `runner.capabilities_changed` event. The slots are
`maxJobs` of the `hello`, else a quarter of the cores, at least one; iOS jobs (`ios-sign` or `ios-linux`) run one at a time per runner.

### Leases and the 90 second rule (D-08)

The lease is the single source of truth for where a job runs. The scheduler places a queued job on a runner; the job
becomes `running` with `runner_id` and `lease_until` (now + 90 s) and the runner gets a `lease_offer` with the id of
the lease. A heartbeat every 30 s renews the leases it lists (idle runners send one too). Every later message about
the job carries the lease id, so a runner that comes back after its lease was lost cannot touch the job: it is
answered with `cancel`. The sweep (`LeaseSweeper`, every 10 s) ends the leases that ran out:

- A job whose steps have **no side effect left to do** is put back in the queue (its running step is `interrupted`,
  the job runs again from its first unfinished step, possibly on another runner).
- A job with a **step with side effects that is not done** (the running one, or one still to come) is
  `waiting_for_resume` and is **never re-queued**: the runner may only be unreachable and still doing it (D-08, D-18).
  `POST /jobs/{id}/resume` runs it again; steps with side effects ask their `alreadyDone` first.
- Heartbeats are idempotent; one that arrives after the lease ran out finds it lost. A connection that drops keeps
  its leases until they run out; a runner that comes back in time shows the leases it holds in its `hello` and they
  continue. The engine restarting does the same as a crash for the jobs on runners (ADR 0006): the recovery marks
  them, and the `hello` of a runner that still holds one is answered with `cancel`.
- A runner that refuses an offer gets none for 15 s (`draining` takes it out until it says otherwise), so a refusal
  cannot become a loop. Cancelling a job on a runner ends it at once and tells the runner.

### Logs, steps and artifacts

- **Log chunks.** A runner numbers its chunks from 1 per lease and keeps each until acknowledged. The engine stores the
  next one, answers a chunk it has with `duplicate` and one that skips ahead with `gap` (nothing is stored; the runner
  sends again from `next`). The lines get the job-wide `seq` of the job's log like local output does, are masked again
  with every secret the engine knows, and reach `GET /jobs/{id}/logs` followers. `job_done` carries the number of the
  last chunk; the engine ends the job only when it has the log up to there.
- **Steps and results.** `step_state` is accepted when it is newer (more attempts, or a later state of the same
  attempt) and ignored otherwise. A job reported `succeeded` while a step is not done is recorded `failed`.
- **Artifacts.** `PUT /runners/jobs/{id}/artifacts/{name}?kind=apk` with `X-Content-SHA256`, `X-Lease-Id` and
  `Content-Length`: the bytes are hashed as they stream into the artifact store, which commits the file only if the
  digest and the size are what was declared, so a wrong or half upload leaves nothing and never replaces a good file.
  The runner must hold the lease of the job. The answer is the `Artifact`. This is the existing store and recorder, so
  retention and downloads work as for local builds.

### What never goes to a runner

- **Steps only the engine runs.** A job is leased as a whole, so a job with one of these steps runs on the engine
  (`RemoteStepPolicy`): `upload.*` (D-09), `git.push`, `git.tag`, `git.releaseBranch` and `github.*` (they push and
  talk to GitHub with the token that stays on the engine, D-05, D-07), `gate` (approvals are the engine's, D-13),
  `guard` (its checks read credentials and ask the stores) and `test` (it judges against the baseline and stores
  the run, both in the engine's database, D-21). `shorebird.release` and `shorebird.patch` may run on a runner
  (ADR 0012). The scheduler never places a job with an engine-only step on a remote runner and the hub refuses
  it again at the offer. The built-in workflows keep these steps in jobs of their own, so their build jobs can
  go to a runner (ADR 0010).
- **Secrets (D-09, ADR 0012, ADR 0016).** Over the authenticated socket, on request, never in the offer: the offer lists
  **keys only**, the runner asks with `secret_request` and gets `secret_value` (the base64 of the bytes)
  **once per lease and key**. What may be asked for is what the steps of this job name in `secretFiles`,
  `secretEnvironment`, `tokenSecret` or `dartDefineSecret` **and** that is the keystore of the project or one of
  its passwords, the Shorebird key of the project or a `dart_defines` file of the project (`RunnerSecretGrants`); the GitHub token, store credentials and anything else are
  `secret_denied`. Each delivery is a `runner.secret_delivered` event (key, never value), and the delivered
  text is added to the log masker. A single-use URL was the other option; the socket is already authenticated,
  bound to the lease and outbound only, and needs no second credential to leak. The socket is not encrypted by
  `xpd` itself (see `--host` above): a runner on another machine should reach the engine through TLS (a reverse
  proxy or a tunnel), because the socket carries signing material. The runner wipes the secret at the end of the
  job and at its start (see The runner agent).
- **The source (ADR 0009).** The offer names the repository (its SSH URL and GitHub id) and the exact commit and
  never a credential; the runner fetches the commit with its own SSH key.

### The runner agent

`xp runner` is the other end of everything above (`apps/xp/lib/src/runner`). What a runner does
while the engine is away for hours, and what happens to its jobs:
[docs/guide/runners.md](../guide/runners.md#when-the-engine-is-away).

```sh
xp runner pair --engine https://xpath.example.com --token xpp_...   # once; xp runners pair <name> made the token
xp runner start [--slots 4] [--one-shot] [--data-dir ~/runner]      # connects out and runs jobs until stopped
xp runner install-service [--slots 4]                                # keeps it running, and lets it update itself
```

- **Pairing.** `pair` checks the engine (`GET /version`), exchanges the pairing token (`POST /runners/pair`) and
  keeps the credential in the secret store of the machine: the Keychain on macOS (service
  `ly.abdurahman.xpath.runner`), an encrypted file in the data directory on Linux (`XP_TEST_FILE_SECRETS=1` forces
  the file, for tests). It is never printed or logged. `runner.json` in the data directory holds who the runner is
  (engine, id, name) and no secret. `--name` only warns when the engine named the runner otherwise: the pairing
  token fixes the name. Pairing again in a paired data directory needs `--force`.
- **Data directory** (`--data-dir`, else `$XP_RUNNER_DATA_DIR`, else `~/.local/share/xpath/runner`):
  `source/mirrors/<key>.git` (the bare cache), `source/worktrees/<key>/<job id>` (fresh worktrees), where the key is
  the project's source key (the GitHub repository id, or `h` and 16 hex digits for another host, ADR 0015),
  `jobs/<job id>` (what a job leaves before it is uploaded), `toolchains/flutter`, `secrets/` (where no tmpfs is
  available), `keychains/`, `state/pgids.json`, and for updates and services `versions/<version>/` (the installed
  `xp` bundles), `current` (a symlink to the version that starts), `update.json`, `service-logs/` (see Runner updates
  and Running as a service).
- **Connection.** Outbound only, with the credential. It reconnects with an exponential backoff (1 s doubling to
  60 s, half of each delay random so that runners that lost the same engine do not come back together) and starts
  the backoff again after a connection that worked. It stops for good when the engine revokes it (close code
  4003), when another connection of the same runner replaced it (4001) or when the credential is refused.
- **Hello and probe.** After the welcome the runner says hello (version, system, architecture, cores, `--slots`
  as `maxJobs`, whether it drains, the leases it still holds) and runs the commands of the probe the engine sends
  (`ProbeExecutor`: `onlyOn`, `requires`, not installed, timeouts, 64 KiB of output). It claims no capability; the
  engine derives them from the results (D-19).
- **Leases.** It accepts an offer within its slots (`--slots`, else a quarter of the cores) and refuses the rest
  with a reason: `busy` (the slots are taken, the job runs here already, or another `ios-sign` job runs: those
  run one at a time), `draining`, `unsupported` (a step this runner has no implementation for). It heartbeats
  every `heartbeatSeconds` of the welcome (30 s), listing its leases, also those whose end the engine has not
  acknowledged yet.
- **The job** runs through the engine's step runner (`JobRunner` and `StepRegistry` of `xp_engine`, the process
  supervisor of `xp_adapters`: every process in its own group, ADR 0003) with the steps the engine lets a runner run
  (`RunnerSteps`). The paths of the engine's disk in the steps (`worktree.path`, `mirror.path`, a working
  directory below it) are translated to the runner's (`LeasePaths`). Every step of the offer starts again, since
  the work of an earlier lease is not on this machine, but the attempts are kept, so that a step with side effects
  asks first whether its work exists (`alreadyDone`). `step_state` frames report each new state of a step.
- **Source (ADR 0009, ADR 0015).** `git.checkout` is `RemoteCheckoutStep`: it fetches the exact commit of the offer
  into the runner's own bare cache (`git fetch origin <sha>` with
  `GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new'`, no global git
  configuration, no prompt), cuts a fresh worktree and verifies `HEAD == sha` before anything runs. SSH records the
  host key of a server it has not seen; a key that changed still fails. A key that cannot read the repository fails
  the job with what to do on its host ("add this runner's SSH key as a deploy key on `<owner/repo>`" on GitHub, "as
  an access key of `<workspace/repo>`" on Bitbucket), a changed host key with "remove the old one (`ssh-keygen -R
  <host>`)", a commit that was never pushed with "push it". The machine needs `git`, `ssh` and its own access to the
  git host (a deploy or access key, or the key of a user). **Test only:**
  `XP_RUNNER_TEST_SOURCE_URL` replaces the URL of every lease (the end-to-end test points it at a local bare
  repository); a real runner never sets it.
- **Logs and reports.** The output of the processes goes to the engine as `log_chunk` frames numbered from 1 per
  lease (up to 500 lines or a quarter of a second each). The runner keeps every chunk, the newest state of every
  step and the end of the job until the engine acknowledges them, and sends them again after a reconnect or after
  a `gap` answer. `job_done` carries the last chunk and the explanation of a failure, and is resent until the
  `done_ack`. Artifacts a build records are uploaded to the engine with their SHA-256 and the lease before the step
  that made them ends (`PUT /runners/jobs/{id}/artifacts/{name}`, tried again on connection errors).
- **Per-job secrets (D-09, ADR 0012).** A step reads a secret like on the engine, from a secret store; here the
  store (`LeaseSecretStore`) asks the engine with `secret_request` the first time a step needs the key (only keys
  of the offer can be asked for) and keeps the answer in the job's secret folder. The folder is 0700, its
  files 0600: on Linux in a tmpfs (`/dev/shm`, else `$XDG_RUNTIME_DIR`), so the secrets never reach the disk; on
  macOS and elsewhere in `secrets/` of the data directory. The secret files of steps (`secretFiles`, bytes as
  they are, so a keystore stays binary) go to the same folder. **The folder is deleted when the job ends, however
  it ends (success, failure, cancel), and again at every start of the runner.** Delivered text is added to the
  runner's masker, so it is hidden in the log before it leaves the machine. For signing material that has to be in
  a keychain on macOS, `TemporaryKeychain` makes a keychain for the job (never the login keychain; created
  unlocked with a random password and set never to lock, over `security -i` so that the password is in no
  argument; added to the search list only if the build needs it, and the list put back when it is deleted);
  nothing the engine delivers today needs it, and a start of the runner deletes any that a crash left.
- **Cancel.** A `cancel` frame (the lease was lost, the job was cancelled, the engine does not know the lease)
  stops the job's process groups (`SIGTERM`, ten seconds, `SIGKILL`, ADR 0003), wipes its secrets and reports
  nothing more.
- **Start-up clean-up.** Before it connects, a start of the runner stops the process groups of steps that a runner
  killed with `SIGKILL` left (the groups are recorded in `state/pgids.json` while a step runs), deletes every
  secret folder and temporary keychain, and removes the work folders and worktrees of jobs. It prints what it
  found. This is what makes "no secret is left after a crash" true.
- **Drain and one-shot.** The first `SIGINT` or `SIGTERM` drains: a `drain` frame, no more offers, the running
  jobs finish and the runner exits 0. The second stops now: the jobs are cancelled, nothing is reported and the
  engine ends the leases when they run out. `--one-shot` takes one job, tells the engine to offer no more and
  exits after the engine acknowledged its end. Exit codes: 0 drained or done, 77 revoked or credential refused,
  73 replaced, 78 not paired, 69 `perl` missing, 75 switched to another version (see Runner updates).
- **Tests.** The agent, the outbox, the step and the secret folder are unit tests with fakes
  (`apps/xp/test/src/runner`); the wiring runs the real step runner against a fake engine on a loopback port
  (tag `process`); `TemporaryKeychain` has a `macos` test on a keychain of its own. `tool/e2e/runner_loss_e2e.sh`
  is the end-to-end proof: it pairs and starts a real runner, gives it two jobs that hold a keystore secret, kills
  it with `SIGKILL`, waits for the production lease (90 s plus the sweep) and checks the loss rule (a job with a
  declared side effect is `waiting_for_resume`, never repeated by itself; one without is queued again, both with
  a `runner.lease_lost` event), then restarts the runner and checks that no secret file, temporary keychain or
  process is left, and that a resumed job that is cancelled wipes its secrets and ends its process group.

### Runner updates (D-24)

A runner runs the version of `xp` its engine runs. The engine says its version in every `welcome`
(`engineVersion`); a runner whose own version is not that one updates itself **between jobs**, never in the middle of
one (`apps/xp/lib/src/runner/update`).

1. **Wait.** At the welcome the runner sees the difference. It says `draining` in its hello (the engine offers it
   nothing), refuses every offer it still gets with `updating`, and lets the jobs it holds finish, however long they
   take. When none is left (the engine acknowledged their end) the agent ends with `AgentExit.updateRequired`. A
   job is never cancelled to update. If the engine goes back to the runner's version meanwhile, the runner goes on
   as it was. A `--one-shot` runner does not update.
2. **Download.** `GET /runners/bundle?os=<os>&arch=<arch>` (the runner token reaches it, ADR 0011) streams the
   `xp` bundle of the engine's own version for the machine as a `.tar.gz`, with `Content-Length` and
   `X-Content-SHA256`. The runner checks the size and the digest before it unpacks anything, and refuses a
   response that does not announce them. The digest guards against a broken download; the engine is trusted for the
   content, as it is for the commands it has the runner run.
3. **Unpack and try.** `tar -xzf` into `updates/`, a check that `bin/xp` exists and is executable, and then
   `bin/xp --version`, which has to print the version the engine runs. A bundle that cannot start (the wrong
   architecture, a missing library) is found out here, while the old version still runs.
4. **Switch.** The bundle becomes `versions/<version>/` and the symlink `current` is moved to it in one step (a
   link made beside it and renamed over it). The version before stays, and when the runner did not run from
   `versions/` yet (the bundle it started from is copied there first), so does the one that ran. The runner then
   starts again as the new version: under a service manager (`XP_RUNNER_MANAGED=1`, which `install-service` sets) it
   exits with **75**, a failure, so that `KeepAlive` and `Restart=on-failure` start `current/bin/xp` again; started
   by hand it starts `current/bin/xp runner start --data-dir ...` itself on the same terminal, waits for it and
   exits with its code (Dart cannot replace a process; the old one holds nothing).
5. **Prove or roll back.** `update.json` records the update: the version before, the version after and how many
   times the new one started without the engine welcoming it. The welcome of the new version clears the record and
   deletes every version but the new one and the one before. A new version that started `3` times and never got a
   welcome (it crashes, or the engine refuses it) is replaced at its next start: `current` goes back to the version
   before, the failed version is remembered in `update.json` so that the runner does not update to it again, and
   the runner restarts. A newer engine version is another version and is tried.

An update that fails (no bundle on the engine, a wrong digest or size, a bundle that does not unpack or start, no
`tar`) changes nothing: the runner logs why (`Cannot update to version X: ...`), goes back to taking jobs as the
version it is and does not try that version again until it restarts.

**Where the bundles come from.** The engine serves the files it finds as `<os>-<arch>/xp.tar.gz`, in the first of
`<data-dir>/bundles/<engine version>/` and `runners/` next to its own `bin` and `lib` (the bundle of `xpd`). The
file is the `xp` bundle that `dart build cli -t bin/xp.dart` makes (`bin/xp`, `lib/libsqlite3.*`, ADR 0001) as a
`.tar.gz` whose top level is `bin` and `lib`. `os` and `arch` are what the runner reports in its hello (`macos` or
`linux`; `arm64`, `x86_64`). `tool/release/bundles.sh` puts the runner bundles of every target it built in the
`runners/` of each engine bundle (see Releases and installation); a bundle it did not build (the macOS ones in an
archive from CI) can go in `<data-dir>/bundles/<engine version>/`. The engine finds no file: `404`, "This engine has no runner bundle for linux-arm64. Put the xp.tar.gz of
this version in ...". The SHA-256 is worked out once per file and kept until the file changes.

**Tests.** `runner_update_test.dart` runs the real runner (`buildRunner`, the real `tar`, a real bundle folder whose
`bin/xp` prints its version) against a fake engine: an outdated runner finishes its job, updates, restarts and
reconnects with the new version in its hello; a wrong digest switches nothing; an engine without a bundle leaves the
runner as it was; a new version that fails to start is rolled back. The restart in the tests is an injectable
`Restarter`.

### Events

`runner.paired`, `runner.connected`, `runner.disconnected`, `runner.revoked`, `runner.capabilities_changed`,
`runner.lease_lost` (with the state the job is in now) and `runner.secret_delivered`; the job events (`job.state_changed`,
`job.step_changed`) are the same as for local jobs.
