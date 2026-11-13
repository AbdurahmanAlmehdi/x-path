---
date: 2026-11-12
topic: ci-triggers-web-dashboard-containers
---

# CI triggers, a web dashboard and per-job containers

## What We're Building

Three features close the main gaps between XPath and a CI service such as Codemagic. Each gets its own plan:

1. **Triggers and PR feedback.** Runs start automatically from pushes, pull requests, tags and cron schedules on GitHub, GitLab
   (including self-managed) and Bitbucket Cloud. Each run reports back on the pull request, and the full release flow
   (push, create PR or MR, merge) works on all three hosts.
2. **A web dashboard, with people and roles.** A separate Vue app that xpd serves on its own origin, at parity with the macOS
   app except for the Mac-only parts. It comes with a lightweight identity model (people with roles who own tokens), so Linux-only
   teams get a GUI and every approval and run records a person.
3. **One Docker container per job, and declarative caching.** Linux runners can opt in to running each job in a fresh container.
   Workflow jobs declare caches (pub, Gradle, CocoaPods or custom), keyed by files, kept locally on each runner.

Today every run is started by hand or by an agent, no status goes back to the git host, the only GUI is the macOS app,
identity is a device token, and jobs run as the runner's user in worktrees, with caches left implicitly in `HOME`.

## Why This Approach

The approaches considered for each area, and why each choice won:

- **Where trigger rules live:** project triggers that point at workflows won over `on:` blocks in the workflow YAML. Built-in workflows
  cannot be edited (`409`), so `on:` in YAML would force a copy of `dev-build` just to build on push. Project triggers
  work with built-ins, can be edited in both GUIs and with `xp`, and keep the workflow document about *what* runs.
- **Getting events to the engine:** polling by default, with webhooks when the engine is public, won over webhooks only or a
  built-in tunnel. Most engines run on `127.0.0.1` or behind NAT. `git ls-remote` works on every host with the SSH access that
  already exists (ADR 0015). XPath runs no relay, which matches the 1.0 non-goal of a hosted relay.
- **Safety of PR runs:** same-repo PRs run without credentials, and fork PRs wait for an approval. A PR runs code that
  someone else wrote on machines that hold signing keys and store credentials, so credentials go only to
  push, tag and schedule triggers.
- **PR feedback on GitHub:** GitHub App check runs won over commit statuses with a PAT. The App also replaces the engine-wide
  PAT with short-lived installation tokens and delivers webhooks. The App is created with GitHub's App Manifest flow, so setup is a
  few clicks. GitLab and Bitbucket get commit statuses plus one MR or PR comment that is edited in place.
- **The web dashboard:** a separate web app (Vue 3 + TypeScript + Pinia) won over a Flutter web target of `apps/xp_desktop`.
  Flutter web is weak at what a dashboard needs: URLs and deep links, browser history, text selection in logs, accessibility and
  first-load size. The cost is screens written twice and Node in the build. The design system already ships
  `xp-tokens.css`, and `packages/xp_api/openapi.yaml` generates the typed client.
- **Identity:** "people and roles, signing in with tokens" won over named web tokens and over real user accounts. Named tokens alone give no
  roles: anyone with a web token could approve a production release. Real accounts bring passwords or OAuth, sessions,
  password reset without email, and an OAuth app per host whose callback URL must reach an engine on a LAN. The middle option gives
  audit and roles. A git-host login can attach to the same person record later.
- **Container execution:** one container per job, with each step run through `docker exec`. This won over a container per step,
  which loses state between steps and starts slower, and over an ephemeral runner per job, which is heavier and changes pairing.
- **Caching:** named caches on each runner, keyed by files. This won over caches shared through the engine, which cost transfer time and engine
  disk, and over fixed built-in caches, which can't be configured. It's the simplest model that still lets a lockfile change invalidate a cache.

## Key Decisions

### Shared

- **Three plans**, one per feature. People and roles form the first phases of the dashboard plan. The triggers plan
  depends on them: approving fork PRs and recording who started a run both need a person. The container plan is
  independent and can run in parallel.
- **Runs record their origin.** `RunRecord` gains `origin`: a person (via their token), an agent (an `mcp` token) or a trigger
  (the trigger id, the event, and the host's actor login). Nothing records this today (`request` JSON only). It needs migration v23 or later,
  plus API, contract tests and `xp_client`.
- **Each plan adds an ADR** (0017 and on). The triggers plan amends ADR 0015 (PRs and merges off GitHub) and the plan's
  non-goals list (GitLab/Bitbucket PRs). The dashboard plan amends the 1.0 non-goal on multi-user accounts and roles and the
  rule that browsers are refused (`allowedOrigins: const []`).

### Plan 1: Triggers and PR feedback

- **Project triggers.** Each trigger is an event plus filters, pointing at a workflow with its dispatch settings:
  - Events: `push`, `pull_request`, `tag` or `schedule`.
  - Filters: branch or tag globs, changed-path globs, a cron expression with a time zone.
  - Dispatch settings: workflow, app, flavors, platforms, bump, inputs.
  - Triggers are stored in the engine and versioned like workflows. They can be edited in the dashboard, the Mac app and `xp triggers`, and
    also through `xp mcp`, where creating one that starts `prod-release` passes a gate.
- **Event sources.**
  - A `RefPoller` follows the existing periodic-loop pattern (`start`/`runNow`/`stop`, injected timers, wired in
    `serve_command.dart`). It runs `git ls-remote` (default every 60 s) on every project and asks the host API for open PRs.
  - Webhooks are registered when the engine has a public base URL. When they deliver, the poller backs off. Deliveries
    arrive on a public route outside `authMiddleware` and are checked by the host's signature or secret token.
  - Duplicate events are dropped by key (project, event, ref, sha).
- **PR run policy.**
  - Same-repo PRs run automatically with no credentials. The planner refuses steps that need a credential or an engine-only
    side effect, so a PR trigger can run `test`, `analyze` and `smoke-build`-style jobs only.
  - A fork PR creates a run waiting on a new gate, `pr_from_fork`, which a person with the developer role or higher approves.
  - Push, tag and schedule triggers get credentials like a manual dispatch. Existing gates such as `prod_release` still apply.
- **GitHub App per engine.**
  - It is created through the App Manifest flow from the dashboard or the Mac app.
  - It takes over from the PAT: fetch over HTTPS with installation tokens, PR create and merge, check runs, webhooks.
  - The PAT stays as a fallback for existing engines, without check runs or webhooks.
  - Check runs link to the run in the web dashboard, which needs an engine base URL setting.
- **GitLab and Bitbucket.**
  - Per-host API token credentials: GitLab with a base URL for self-managed instances, Bitbucket Cloud.
  - Webhooks, commit statuses, one MR or PR comment edited in place, and the full release flow (push the release branch and tag, create and
    merge the MR or PR). `prod-release` then works on all three hosts.
  - The `GitHubClient` port is generalised into a host-neutral port with one adapter per host. `_refuseGitHubSteps` turns into a check for
    host capabilities.

### Plan 2: Web dashboard, people and roles

- **Identity first (phases 1 to 2).**
  - A `person` record (name, role: viewer, developer, releaser or admin) owns device tokens of every kind.
  - Upgrading creates one admin person who owns the existing tokens.
  - Approvals check the role instead of only the token kind: releaser or higher for `prod_release`, `push`, `merge`, `rollout` and
    `store_submission`; developer for `pr_from_fork`. `mcp` tokens still never approve.
  - An admin creates a person and gets a one-time sign-in code. The code is exchanged for a `web` token. The
    `device_token.kind` CHECK constraint needs a table-rebuild migration (`foreignKeysOff`).
- **The app.**
  - `apps/xp_web`: Vue 3, TypeScript, Composition API, Pinia, Vite.
  - A typed client generated from `openapi.yaml`, with a CI check that it is up to date.
  - `xp-tokens.css` for the Run Sheet look, light and dark.
  - Vitest for stores and components, Playwright end to end against a real `xpd`.
  - Type definitions ship with it.
- **Serving.**
  - xpd serves the built files on the same origin as the API: no CORS, nothing extra to deploy.
  - The Linux bundles, the Docker image and the Mac app's embedded engine include the files.
  - Browser WebSockets (`/events`, job logs) authenticate with a short-lived single-use ticket from an authenticated HTTP call, with an
    Origin check against the engine's own origin. Runner sockets stay closed to browsers.
- **Scope.** Parity with the Mac app except the Mac-only parts (local engine agent, CLI link, menu bar extra, Remove XPath):
  - project overview, dispatch, runs and job view with live logs, approvals, releases, tests, runners and pairing, storage
  - the workflow builder (visual plus YAML)
  - credentials (file upload in the browser)
  - add project (git URL, or a path on the engine's machine)
  - triggers
  - people and roles (admin)

### Plan 3: Docker per job and caching

- **Opt-in per runner.**
  - `xp runner --isolation docker` and `xpd serve --isolation docker` for the engine's local runner. Host mode stays the default.
  - Linux first. `ios-linux` jobs (ADR 0014) always run on the host.
  - The runner reports a `docker` capability, so a job that names an image only goes to a runner that can run it.
- **One container per job.**
  - At lease start the runner creates the container with mounts for the worktree, the pinned Flutter SDK from `toolchains/`, the cache
    volumes, and the job's tmpfs secret folder (read-only).
  - `JobRunner` runs each step through `docker exec` instead of the perl process-group trampoline (ADR 0003).
  - Cancel is `docker kill`. A restarted runner removes containers by label, the way it reaps pgids today.
  - The container is removed at job end.
  - Secrets still reach steps only as 0600 files and allowlisted environment variables.
- **Images.**
  - XPath publishes an Android build image (JDK 17, Android SDK, no Flutter), versioned with XPath.
  - A workflow job may name its own image (`container: {image: ...}`).
- **Caching.**
  - A workflow job lists `cache: [pub, gradle, cocoapods]` or custom entries `{name, paths, key: [files…]}`.
  - Each runner keeps caches locally: named Docker volumes, or folders under the runner data dir in host mode. They are wired through
    `PUB_CACHE`, `GRADLE_USER_HOME` and `CP_HOME_DIR`, which pass through the environment allowlist.
  - A changed key file starts a new cache seeded from the previous one.
  - Caches show in Storage with their size and a clear action, and are covered by housekeeping on runners as well as the engine.
  - Nothing is uploaded to the engine.

## Codebase anchors

From the pattern review (paths relative to the repo root):

- Dispatch: `apps/xpd/lib/src/api/workflows/workflows_routes.dart`, `packages/xp_engine/lib/src/dispatch/workflow_dispatcher.dart`
  (`dispatch`, `plan`, `again`, `_refuseGitHubSteps`), `dispatch/step_planners.dart`, `workflows/workflow_parser.dart`.
- Runs and jobs: `scheduler/run_record.dart` (no origin field), `jobs/job_record.dart`, `jobs/job_runner.dart`.
- Git and GitHub: `git/git_service.dart` (`lsRemote`, `fetch`), `xp_adapters/lib/src/git/cli_git_service.dart`, `git/github_client.dart`,
  `xp_adapters/lib/src/github/http_github_client.dart`, `git/github_token_service.dart`, `xp_api/lib/src/project.dart` (`host`,
  `isOnGitHub`).
- HTTP and auth: `apps/xpd/lib/src/api/api_handler.dart`, `middleware.dart` (`authMiddleware`, `runnerScopeMiddleware`),
  `xp_api/lib/src/device_token_kind.dart`, `xp_engine/lib/src/tokens/token_service.dart`, `api/tokens/tokens_routes.dart`.
- Events and sockets: `api/events_route.dart`, `api/jobs/job_logs_route.dart`, `runners/runner_connect_route.dart` (all
  `allowedOrigins: const []`), `xp_api/lib/src/events.dart`.
- Periodic loops to copy: `approvals/approval_sweeper.dart`, `releases/release_watcher.dart`, `housekeeping/housekeeping_schedule.dart`.
- Server: `apps/xpd/lib/src/server/xpd_server.dart` (no static files today).
- Processes: `steps/step_context.dart` (`ProcessCommand`), `process/process_environment.dart` (allowlist),
  `xp_adapters/lib/src/process/io_process_supervisor.dart` (ADR 0003).
- Runner: `apps/xp/lib/src/runner/runner_agent.dart`, `runner/job/leased_job.dart`, `runner/runner_paths.dart`,
  `runner/secrets/secret_area.dart`, `Dockerfile.runner`.
- Probes and capabilities: `probe/runner_probe.dart`, `scheduler/local_capabilities.dart`, `scheduler/capability.dart`.
- Storage: `housekeeping/` (engine), `apps/xpd/lib/src/api/storage/storage_routes.dart`, `xp_api/lib/src/storage.dart`.
- Conventions: next migration v23 (`xp_adapters/lib/src/sqlite/migrations.dart`, golden `snapshots/v23.sql`); next ADR 0017;
  100% coverage for `xp_api`, `xp_client`, `xp_engine`, `xp_repositories`; layer rules in `tool/lib/src/layer_rules.dart`.

## Prior art

Research done on 2026-11-12. Sources:
- public docs read in Chrome
- the owner's signed-in Codemagic dashboard, read only
- REA run on Woodpecker's public CI, using a throwaway headless Chrome
- web search

REA could not attach to the owner's Chrome, so how Codemagic streams logs is still unknown.

### Triggers

- **Codemagic** ([triggers](https://docs.codemagic.io/yaml-running-builds/starting-builds-automatically))
  - Events are `push`, `pull_request` and `tag`.
  - Branch patterns use `include` and `source` and are read top-down. For a PR, `source: false` matches the target branch.
  - "Cancel outdated webhook builds" cancels earlier builds of the same branch.
  - It honours `[skip ci]`.
  - Changeset filters skip a build only after the clone, so a skipped build still uses a machine.
  - PR builds test the merge commit.
- **Concourse** ([resources](https://concourse-ci.org/docs/resources/)) and **Jenkins** `notifyCommit` poll by default. A webhook only asks for
  an immediate check, and its payload is ignored. This is the model XPath adopts.
- **Buildkite** ([canceling builds](https://buildkite.com/docs/pipelines/configure/canceling-builds)) can skip intermediate builds, which drops
  queued ones, or cancel them, which kills running ones. Both take a branch filter.
- **Woodpecker** ([project settings](https://woodpecker-ci.org/docs/usage/project-settings))
  - Forks need approval by default.
  - It has run states `blocked`, `declined` and `killed` (superseded).
  - A pipeline waiting for approval has a "Changed files" tab, so the reviewer sees the diff before approving.
- **GitHub Actions** ([fork approvals](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks)) bases trust on the
  author's history: one merged typo PR is enough to be trusted. `pull_request_target` runs fork code with secrets, the "pwn request" problem.
  **GitLab** ([MR pipelines](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/)) never gives protected variables to fork MRs.

### Host APIs

- **GitHub App Manifest flow** ([docs](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest))
  - The browser POSTs the manifest, and GitHub redirects back with a single-use `code`, valid for an hour.
  - `POST /app-manifests/{code}/conversions` returns the app id, the PEM key and the webhook secret.
  - The redirect happens in the browser, so **it works for an engine behind NAT**. Create the App with `hook_attributes.active: false`,
    and turn the webhook on once the engine is public.
  - **Atlantis** ([access credentials](https://www.runatlantis.io/docs/access-credentials.html)) and **Probot** use this flow. Atlantis warns that the setup page is
    open until credentials exist.
- **GitHub permissions and tokens**
  - Permissions: `checks`, `contents`, `pull_requests` and `statuses` (write), `metadata` (read).
  - Events: `push`, `pull_request`, `create`/`delete`, `check_run`, `check_suite`, `installation*`.
  - Installation tokens live one hour and can be **narrowed to one repository and fewer permissions**.
  - Check runs ([docs](https://docs.github.com/en/rest/checks/runs)):
    - only Apps can write them
    - 50 annotations per request
    - up to 3 action buttons
    - `external_id` and `details_url` link back to XPath
- **GitLab** ([commit statuses](https://docs.gitlab.com/api/commits/), [webhooks](https://docs.gitlab.com/user/project/integrations/webhooks/))
  - `POST /projects/:id/statuses/:sha` with a `name` per check. It can answer 409 while an update is in progress, so retry.
  - MR comments are notes, which can be edited.
  - Webhooks carry the plaintext `X-Gitlab-Token`. Since 19.x they can also be signed with Standard Webhooks (`webhook-id`, `webhook-timestamp`,
    `webhook-signature`).
  - Hooks are paused after 4 failures and disabled after 40, so acknowledge fast and queue the work.
- **Bitbucket Cloud** ([webhooks](https://support.atlassian.com/bitbucket-cloud/docs/manage-webhooks))
  - Build statuses go to `commit/{sha}/statuses/build`, with a `key` and states INPROGRESS, SUCCESSFUL, FAILED and STOPPED.
  - Webhooks carry `X-Hub-Signature: sha256=…`, but only when a secret is set.
  - **App passwords are being removed** (2026), so XPath uses **scoped API tokens**. The REST API takes email + token; git over HTTPS takes
    username + token.
  - There are no PR refs to `ls-remote`, so Bitbucket polls PRs through the REST API.

### Web dashboards

- **Codemagic** (signed-in dashboard)
  - App cards with the last build status.
  - A global builds list filtered by app, workflow, status, branch and tag. Rows show the SHA, the commit, artifact chips and the duration.
  - The build page has metadata on the left ("Started by: github webhook", machine, branch, commit), then artifacts.
  - On the right, the steps are listed with durations and a log download for each step. The failed step opens inline, with a deep link
    (`?open-step=`).
  - Workflow settings have tabs for the editor, webhooks, scheduled builds and repository.
  - Roles are only Admin and Member ([teams](https://docs.codemagic.io/getting-started/teams)). XPath's releaser role goes beyond that.
- **Woodpecker** (an open-source Vue 3 UI)
  - The browser session is a JWT in a cookie, with a CSRF token injected into the page. API bearer tokens skip CSRF.
  - Live events and logs come over **SSE**, sent with `x-accel-buffering: no` so reverse proxies don't buffer them
    ([router](https://github.com/woodpecker-ci/woodpecker/blob/main/server/router/api.go)).
  - **Concourse** uses the same pattern: a cookie plus an `X-Csrf-Token` header.
- **OWASP** ([WebSocket cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html)):
  - check `Origin`
  - authenticate with a short-lived ticket
  - never put long-lived tokens in URLs

### Containers and caching

- **Codemagic** ([caching](https://docs.codemagic.io/knowledge-codemagic/caching)) caches paths. The cache is saved after a green build, expires after 14
  days, and is capped at 10 GB.
- **Bitrise** and **GitHub Actions** use keys with fallbacks. GitHub restores only from the run's own branch, the PR base or the default branch,
  which blocks cache poisoning.
- **GitLab** has `cache:key:files`, `fallback_keys` and a `pull | push` policy, and keeps protected and unprotected branches apart.
- **Gradle** on ephemeral CI ([blog](https://blog.gradle.org/gradle-on-ephemeral-ci-2)): a shared read-only `GRADLE_RO_DEP_CACHE` with a
  per-job writable `GRADLE_USER_HOME`. Gradle's file locks don't work between containers.
- **Cirrus Labs Flutter and Android images** are reportedly unmaintained since May 2026. This is unconfirmed, but XPath should build its own image either way.

### What it changes in this design

1. **A webhook is a hint (Plan 1).** A webhook delivery or a poll diff only queues a "ref check".
   - The engine resolves the ref and deduplicates on `(trigger, event, ref, sha)` with a unique index. It also keeps
     the host delivery ids (`X-GitHub-Delivery`, `webhook-id`, `X-Request-UUID`).
   - Pushes are debounced per ref (10–30 s, newest SHA wins).
   - The poller lists `refs/pull/*/head` on GitHub and `refs/merge-requests/*/head` on GitLab, and uses the REST API on Bitbucket.
2. **Supersede and new states (Plan 1).**
   - Each trigger takes `supersede: none | queued | running`. Tag and release runs are never superseded.
   - `[skip ci]` is honoured.
   - Path filters are checked on the engine before a runner is claimed. A missing base (new branch, force-push) means "run".
   - New run states: `declined` and `superseded`. These map to GitHub `cancelled`, GitLab `canceled` and Bitbucket `STOPPED`.
3. **Trust and approvals (Plan 1).**
   - Trust follows the PR's head repository, not the author's history.
   - The `pr_from_fork` approval shows the changed files and flags changes to workflow or build files.
4. **The GitHub App (Plan 1).**
   - Created through the manifest flow from the dashboard, with the webhook inactive until the engine has a public URL.
   - The setup route is admin-only.
   - Runners get **per-job installation tokens narrowed to one repository with read-only contents**, so they no longer need an SSH deploy key
     for GitHub.
5. **Host feedback (Plan 1).** One `HostFeedback` port with three adapters.
   - Check names are `xpath/<workflow>/<flavor>`. Bitbucket gets a short hash as its `key`.
   - Each PR gets one sticky comment.
   - GitLab webhooks are checked by token and, where the instance signs them, by signature.
6. **Browser sessions (Plan 2).**
   - The one-time sign-in code becomes a `web` token held in an **HttpOnly, Secure, SameSite=Strict cookie**.
   - Requests that change something need a CSRF header.
   - `xp`, `xp mcp` and the Mac app keep bearer tokens.
   - Sockets use a 30-second single-use ticket and check `Origin`. Read-only log tails may use SSE instead.
7. **Cache trust (Plan 3).**
   - A cache key hashes the preset, the key files, the image digest and the runner's OS and arch.
   - PR jobs restore from the default branch but write to a PR namespace, so a release never restores a cache a PR wrote.
   - Gradle uses `GRADLE_RO_DEP_CACHE` (read-only, shared) plus a per-job `GRADLE_USER_HOME`.
   - CocoaPods caching is macOS host mode only.
8. **Container hygiene (Plan 3).**
   - Containers run with `docker run --init`, and cancel does `docker stop -t 20` then kill.
   - Gradle runs with `--no-daemon` and an explicit JVM memory cap.
   - The UID matches the runner (`--userns=keep-id` on rootless Podman), and Flutter's SDK gets a `safe.directory` entry.
   - `--device /dev/kvm` only on runners that opt in to emulators.
   - XPath publishes its own Android build image.

## Open Questions

- **URL space for the dashboard.** The API lives at the root (`/projects`, `/runs`, …), so SPA routes would collide with it. Serve the UI
  under `/ui/`, or move the API under `/api/v1` with the old paths kept as aliases? The plan should pick one.
- **Live updates for the browser.** Use WebSocket with a ticket for `/events` and logs, or SSE for read-only streams (simpler behind proxies)?
- **Check run granularity.** One check run per job (workflow × flavor × platform, suggested), or one per run?
- **Debounce window and default supersede.** Should the default be 15 s and `queued`?
- **A trigger that names `prod-release`.** Allowed with the usual gates, or refused?
- **A job image on a host-mode runner.** Refuse the job, or require the `docker` capability so it waits for a Docker runner?
- **Docker on macOS runners.** Out of scope for now (iOS needs the host Xcode)?
- **TypeScript coverage policy for `apps/xp_web`.** Match the 90% glue floor, or 100% for stores and the client?
- **Node in CI and releases.** Build the web UI in the Linux release workflow and embed it in `xpd` bundles, or ship it as a separate asset?
