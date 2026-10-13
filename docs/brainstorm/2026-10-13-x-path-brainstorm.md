---
topic: XPath, a self-hosted release tool for Flutter apps
date: 2026-10-13
source: grilling session (4 rounds), Mataa release-tooling work
---

# XPath brainstorm

Replaces the "unified script" step of the Mataa release-tooling roadmap. Everything below
was put to the owner as a question with a recommendation and accepted unless noted.

## Product

- Name **XPath**. Repo `AbdurahmanAlmehdi/x-path` (personal profile, no org), private until
  the first release. CLI `xp`, engine `xpd` (macOS ships `/usr/bin/xpath`).
- Apache-2.0. Public and self-hosted from day one; a hosted cloud version comes later on the
  same engine API.
- One 1.0 release with every feature (owner rejected milestone releases). Internal build
  order: engine, then Mac app + `xp` + MCP, then runners, then the workflow builder.

## Architecture

- Dart and Flutter throughout. `xpd` is a pure Dart AOT binary for macOS and Linux; the Mac
  app is Flutter desktop. Chosen over Swift: target users are Flutter teams, one language for
  every machine, web dashboard nearly free later.
- `xpd` owns SQLite, secrets, job queue and steps. LaunchAgent on the Mac, service on the Mac
  mini / Linux.
- Clients (Mac app, `xp`, MCP, runners) use HTTP/JSON + a WebSocket event stream, described
  by OpenAPI, one bearer token per device. One owner per engine, no accounts or roles.
- Secrets stay on the engine machine (Keychain on Mac, encrypted file on Linux); runners get
  them per job and wipe them after. Runners never hold a signing key or password.
- Runners dial out to the engine (WebSocket, one-time pairing token); reachability is the
  user's network or Tailscale. No relay in 1.0. Runners advertise capabilities
  (`ios-sign`, `android`, `flutter`, `swift-linux`) and slots; `ios-sign` runs one job at a
  time; others default to cores / 4. Runners self-update to the engine's version.
- MCP: agents can do anything; prod release, prod OTA patch, store submission, pushes, merges
  and deletes wait for approval in the app (configurable per project).

## Projects and builds

- Project = one git repo identified by its remote, holding one or more apps (melos
  monorepos included). Flutter is first-class; anything else runs via command steps.
  "Swift-linux" capability = pure Swift packages that build and test on Linux.
- Scan (read-only): framework, flavors, entry points, bundle/application IDs per flavor,
  version sync (pubspec + literal plists), Shorebird, signing teams, keystore reference,
  CocoaPods vs SPM, remote and branch layout against the release model.
- XPath writes to a repo only release-model git changes: version commits, tags,
  `release/*` branches, pushes, PR merges. Profiles, workflows, history, secrets, manifests,
  artifacts live in XPath's own storage.
- Every job runs in a fresh worktree of the exact commit or tag; never the working folder.
- Tools: Flutter version pinned per project (`.fvmrc`), via fvm if present else XPath's own
  cache; Shorebird, gh, firebase managed per machine; Xcode detected only.
- Release model default: `release/x.y.z`, `v<x.y.z>+<build>`, patch `v<x.y.z>-p<N>`,
  monotonic global build numbers, `main` = what's live. Configurable per project.
- Workflows: stages (sequential) of jobs (parallel) of steps; each job declares
  capabilities, flavor/platform matrix, conditions, approval gates. Built-ins: dev build, prod
  release, Shorebird patch. Builder = visual editor + YAML view. Stored in XPath's DB,
  import/export as YAML (a repo may carry one; the scan detects it).
- Tests: `flutter test` with per-test results, `flutter analyze`, baseline comparison so only
  new failures stand out. Integration tests on devices later.
- GitHub only in 1.0, behind a host interface.

## Stores

- Apple with an ASC API key: full status. Apple ID + app-specific password: upload, public
  live version (iTunes lookup), manual "approved" button.
- Play with a service account: full status and upload. Without: manual upload and a
  "Play: live" button. (No Play service account exists for any current app.)
- Release PR merge is enabled once both stores show live, by API or by hand.

## Extras in 1.0

Artifact retention + "free up space"; Firebase App Distribution; R8 / dSYM / Shorebird
symbol storage; release notes (Slack and WhatsApp text); macOS + Slack notifications;
pre-flight checks (closed App Store train, build-number reuse, Play target SDK); reminder to
raise `min_version_*` in Remote Config after a forced update is approved.

## Distribution

Notarized DMG on GitHub Releases, Sparkle auto-update, Homebrew cask in a personal tap.
Developer ID Application certificate from team AFBD5TBR5U (to be created; none exists yet).
Linux: single binary, install script, Docker image.

## Defaults (stated, not objected to)

No telemetry; build logs kept 90 days; light and dark themes.

## Migration

Both `ship.sh` scripts (Mataa, oneavant) stay until XPath ships a real prod release of each
app: Mataa customer first, then captain, then oneavant apps. Mataa Phase 4 cleanup (Fastlane,
broken CI, old scripts) proceeds separately.

## Known facts that shape the plan

- All current apps are Flutter. Only `room_scene_spike` uses Flutter's SPM integration; none
  use Swift packages directly.
- Flutter versions disagree today: local 3.47.4, oneavant pin 3.47.6, Shorebird bundled 3.44.6.
- Prod Apple team (FANNAK) has no ASC API key; uploads use Apple ID + app-specific password.
- Toolchain on the owner's Mac: macOS 26.7.1 arm64, Xcode 27.1, Swift 6.4, Flutter 3.47.4 /
  Dart 3.13.3, gh 2.96.0, Shorebird 1.6.113.
