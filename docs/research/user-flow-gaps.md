# User-flow gaps (research, 2026-10-13)

Flows: install/onboarding, add project, credentials, store versions, dispatch (dev / prod /
patch), live job, MCP approval, tests with baseline, release lifecycle, runners, workflow
builder, artifact cleanup, updating XPath, uninstall.

## Must resolve (proposed defaults)
- M1 Keychain vs headless: Mac mini runs a LaunchAgent under an auto-login user; locked
  Keychain => engine starts "secrets locked", queues jobs, notifies; never prompts. Linux key in
  a root-only file or systemd credential (at-rest protection only).
- M2 Approvals when app closed/remote: app manages several engines; `xp approve` works; MCP
  tokens can never approve.
- M3 Worktree source: engine keeps its own bare mirror keyed by GitHub repo id; folder only
  identifies the repo; follow GitHub redirects on rename.
- M4 Build numbers: per-app counter in engine DB, seeded from max(stores, tags, DB), allocated
  atomically at dispatch, never returned. One prod release/patch per project at a time.
- M5 Existing tag: same SHA => reuse (resume); different SHA => fail preflight; never force.
- M6 Release base branch per project (Mataa: `dev`).
- M7 Idempotent steps: completion recorded per step; resume from first unfinished; upload
  checks store for existing build number first.
- M8 Sleep/crash: power assertion during jobs; on restart mark interrupted; never auto-resume
  a side-effect step; offer "resume from step".
- M9 Unsupported layout: show detected vs missing, manual fill; unknown => command-steps project.
- M10 Approvals bind to (project, action, SHA, version); first decision wins; expire 24h as
  denied; MCP gets a pending id and polls.
- M11 Release states: draft, building, uploaded, in_review, rejected | approved, live, merged;
  abandoned. Rejection => "new build, same version".
- M12 Signing on runners: secrets in temp keychain / tmpfs per job, wiped at job end and runner
  start; heartbeat loss 90s => fail, never re-queue side-effect stages; uploads run on the
  engine; revoke invalidates token.
- M13 Version skew: engine updates only when idle; app accepts engine one minor behind
  (OpenAPI version); DB backup before migration; runners update between jobs.

## Defaults
D1 engine-down banner + cached read-only view; D2 DB workflow wins, scan offers import with
diff; D3 credential test on save + daily health check, fail preflight on expiry; D4 storefront
per app, 10-min status cache; D5 patch uses Flutter version recorded at release; D6 log resume
by offset, secret masking, 90 days; D7 only the app loosens gates; D8 baseline = last green on
base branch; D9 PR conflict fails with link, manual "live" records who/when; D10 pairing token
single-use 15 min, engine probes capabilities; D11 jobs snapshot workflow version, versioned
YAML schema, line-level import errors; D12 never delete artifacts/symbols of live or in-review
builds; D13 uninstall unloads agent, revokes runners, optional data wipe, brew zap.
