# XPath: product brief for design

The source of truth for design work. Read it fully before proposing anything.

## 1. What XPath is

XPath is a release tool for teams that build Flutter apps. You point it at an app's git repo
and it takes the app from "code on a branch" to "live in the App Store and Google Play":
it builds the iOS and Android versions, runs the tests, signs them, uploads them to the
stores (and to testers through Firebase), tags the release in git, and then watches the stores
until Apple and Google approve it. When both stores are live, one button merges the release
into `main`.

It runs on the developer's own machines, not in the cloud. A small background service (the
**engine**) does the work; the **Mac app** is how people see and drive it. A Mac mini or a
Linux box can join as a **runner** to share the build load. AI agents (Claude Code and others)
can drive it too, but risky actions wait for a human to approve them in the app.

It replaces hand-maintained release scripts. Open source, free, self-hosted.

Mood in one line: **Xcode meets Railway meets GitHub Actions.** Native-Mac precision and
calm, Railway's clarity about what is running where, and GitHub Actions' readable pipeline of
jobs and steps with live logs.

## 2. Who uses it

- **The release owner** (primary): a mobile lead who ships two to five Flutter apps, each with
  dev and prod flavors, to both stores. Opens XPath several times a day: "what's live, what's
  in review, did last night's build pass, ship the hotfix". Expert, keyboard-heavy, impatient
  with chrome.
- **Other developers on the team**: dispatch a dev build for testers, read a failing log.
- **AI agents** through MCP: start builds, edit workflows, ask for approval. They never see
  the UI, but their requests show up in it and must be obviously "from an agent".

## 3. Surfaces

- **Mac app** (the design target): Flutter for macOS, one window plus a menu bar extra. Works
  against a local engine or a remote one (the Mac mini); can switch between engines.
- `xp` CLI and `xp mcp`: text only, not in scope for visual design, but the app's vocabulary
  must match theirs.
- A web dashboard may come later from the same Flutter code, so avoid Mac-only tricks that
  cannot be drawn in Flutter.

## 4. Vocabulary

| Term | Meaning |
|---|---|
| Engine | The background service doing the work. Local ("This Mac") or remote ("mac-mini"). |
| Project | One git repo, e.g. `mataa_new_app`. Holds one or more apps. |
| App | One Flutter app inside a project (a monorepo can hold a phone app and a tablet app). |
| Flavor | A build variant of an app, usually `dev` and `prod`, each with its own bundle ID and store listing. |
| Workflow | A recipe: stages that run in order, each with jobs that run in parallel, each with steps. Built-ins: Dev build, Prod release, Shorebird patch, Tests. |
| Job | One run of a workflow job on one machine. Has steps and a live log. |
| Step | One action inside a job: "Check source", "Bump version", "Build iOS", "Upload to App Store", "Tag release". |
| Runner | A machine that runs jobs. Has capabilities (`ios-sign`, `android`, `flutter`, `swift-linux`) and slots. |
| Release | A version heading to the stores, e.g. `5.4.1 (3283)`, with its own lifecycle. |
| Patch | An over-the-air code update (Shorebird) to an existing release, e.g. `5.4.1-p2`. |
| Approval | A request to do something risky (prod release, store submission, merge) that a human must approve. |
| Artifact | A built file: IPA, AAB, APK, mapping, dSYM, manifest. |
| Scan | What XPath detects when you add a project: apps, flavors, IDs, versions, signing, problems. |
| Baseline | The last green test run on the base branch; new failures are shown against it. |

## 5. Statuses

Every status needs a label and an icon, never colour alone.

- **Job and step:** queued, waiting for runner, waiting for approval, running, succeeded,
  failed, cancelled, skipped (already done), interrupted (engine restarted mid-job).
- **Release:** draft, building, uploaded, in review, rejected, approved, live, merged,
  abandoned.
- **App Store (per release):** processing, ready to submit, waiting for review, in review,
  pending developer release, rejected, ready for sale (live), phased rollout (day 3 of 7),
  unknown (no API key: only the public live version is known).
- **Google Play (per release):** draft, not sent for review, in review, approved not published,
  not approved, published (live), rolling out (20%), unknown (no service account).
- **Firebase (testers):** uploaded, distributed to groups.
- **Approval:** pending, approved, denied, expired.
- **Runner:** online idle, online busy (2 of 3 slots), offline, lost mid-job, updating.
- **Engine:** connected, reconnecting, unreachable (showing cached data), secrets locked.
- **Scan findings:** error, warning, info, each with a suggested fix.
- **Credentials:** verified, expiring soon, expired or rejected, missing.

## 6. What the app does (areas)

1. **Projects sidebar** and an engine switcher.
2. **Project overview:** each app and flavor with its local version, the latest TestFlight /
   Play testing build, and the live store version; recent jobs; active release.
3. **Dispatch:** pick workflow, flavor(s), platform(s), ref (branch or tag), version bump; see
   which runner will take it and which approvals it will need.
4. **Job view:** pipeline of stages/jobs/steps with live status, live log with search, cancel,
   re-run, resume from a step, artifacts.
5. **Releases:** each release with an App Store lane and a Play lane, manual "approved" /
   "live" buttons when no API is configured, release notes, and the Merge button once both
   lanes are live. Reminder to raise the minimum version after a forced update.
6. **Approvals inbox:** requests from people and agents, bound to an exact commit and version.
7. **Tests:** latest run against the baseline; new failures first.
8. **Runners:** machines, capabilities, slots, current jobs, pairing a new one.
9. **Workflows:** list, visual builder with a live YAML view.
10. **Credentials:** per team / app / flavor, with verification state.
11. **Storage:** artifacts by app and flavor, retention, "free up space".
12. **Onboarding and Add project:** install the engine, pick a folder, review the scan.
13. **Menu bar extra:** running jobs, pending approvals, quick dispatch.

## 7. Data the engine returns

Design within these fields.

- **Project:** name, git remote, default base branch, apps, gates (which actions need approval).
- **App:** name, path in repo, framework (Flutter), store country, next build number.
- **Flavor:** name, iOS bundle ID, Android application ID, Shorebird on/off, prod or not,
  local version, latest TestFlight build, latest Play testing build, live store version per
  platform, credential states.
- **Job:** workflow, trigger (person, agent, schedule), commit SHA and message, ref, runner,
  state, started, duration, steps (name, state, duration, log offset), artifacts.
- **Log line:** sequence, timestamp, stream (stdout/stderr), text (may contain ANSI colour).
- **Release:** version, build, tag, state, App Store state, Play state, phased rollout %,
  release notes, PR link, timeline of state changes with who/what changed them.
- **Approval:** action, project, version, commit SHA, requested by (person, device or agent
  name), requested at, expires at, decided by.
- **Runner:** name, OS, arch, capabilities, slots used/total, Xcode and Flutter versions, last
  heartbeat, current job.
- **Test run:** passed, failed, skipped, duration, new failures vs baseline, fixed vs baseline.
- **Artifact:** kind, size, sha256, created, pinned, reason it's kept.
- **Scan finding:** severity, message, file path, fix.

## 8. Platform constraints

- macOS app built in Flutter. Native-feeling: proper sidebar, toolbar, keyboard shortcuts
  (Cmd-K command palette, Cmd-R re-run, Cmd-. cancel), context menus, translucent sidebar where
  Flutter can do it.
- Light and dark mode. Contrast 4.5:1 for text.
- Logs and identifiers (SHAs, versions, bundle IDs) in a monospace face with tabular figures.
- Dense but calm: a release owner scans a lot at once, but nothing should shout unless it
  needs a human.
- English only at launch, but no layout that breaks with longer strings.
- Window from 1100×700 up to 1728×1117.

## 9. Sample data

Use these so screens feel real and the numbers agree.

**Engines:** "This Mac" (MacBook Pro, local, connected) and "mac-mini" (remote, connected).

**Projects**
- `mataa_new_app` (Mataa customer app): flavors `dev` (com.mataaa.dev) and `prod`
  (com.sixdtec.mata / com.mataaa). Local version 5.5.0 (3284) on `dev`. Release 5.4.1 (3283):
  App Store "waiting for review", Play "in review", forced update. Live: iOS 5.3.6, Android
  5.3.7. Shorebird patches on 5.3.7: p1, p2.
- `mataa_captain` (driver app): release 1.3.7 (31) App Store "in review", Play "published".
  Note: 1.3.6 (30) was rejected by the upload with "train closed" and rebuilt as 1.3.7.
- `oneavant_guest_experience` (melos monorepo): apps `mobile_app` and `tablet_app`, flavors
  `dev`, `iniala`, `oneavant`.

**Runners:** "This Mac" (macOS arm64, `ios-sign` `android` `flutter`, 1/3 slots, Xcode 27.1,
Flutter 3.47.4); "mac-mini" (macOS arm64, `ios-sign` `android` `flutter`, idle);
"linux-builder-01" (Ubuntu x64, `android` `flutter` `swift-linux`, 2/4 slots).

**Running job:** Prod release, `mataa_new_app` prod, 5.4.1 (3283), commit `9a3bc0d` "chore(release):
5.4.1+3283", started by Abdurahman 14:02. Stages: Preflight (done 0:41) → Build (iOS running
on This Mac 6:12, Android done on linux-builder-01 4:55) → Upload (waiting for approval) →
Record. Log tail: `Running pod install...`, `Building com.sixdtec.mata for device (ios-release)...`,
`Xcode archive done. 312.4s`.

**Pending approval:** "Submit 5.4.1 (3283) to App Store", requested by agent "Claude Code
(xp mcp)" at 14:09, expires in 23h 51m, commit `9a3bc0d`.

**Tests:** `mataa_new_app` dev: 1,284 passed, 27 failed (all 27 in the baseline), 0 new
failures, 3 fixed since baseline, 2m 41s.

**Storage:** 51.2 GB of artifacts, 38.9 GB reclaimable (pinned: 5.4.1 in review, 5.3.7 live).

**Scan finding examples:** warning "iOS dev bundle ID `com.mataaa.captain.dev` differs from
Android `com.mataa.captain.dev`"; error "No App Store Connect API key for team FANNAK: status
will show the live version only"; info "Shorebird enabled for prod only".
