# XPath handoff

## Goal

Build XPath 1.0. It is an open-source (Apache-2.0), self-hosted release tool for Flutter apps.
- **Engine:** `xpd`, written in Dart.
- **Clients:** a Flutter macOS app, the `xp` CLI, `xp mcp` (an MCP server for agents) and `xp runner` (remote runners).
- It builds, tests, signs, uploads, tags and tracks releases to App Store Connect, Google Play, Firebase App Distribution and Shorebird.
- It writes nothing to the app repos except release-model git changes.

The source of truth is [docs/plan/2026-10-13-feat-xpath-release-tool-plan.md](docs/plan/2026-10-13-feat-xpath-release-tool-plan.md). Read all of it before doing anything. In particular:
- **Decisions D-01..D-24:** settled with the owner. Don't reopen them without asking.
- **Coverage policy:** chosen by the owner. 100% for logic packages and blocs, a 90% floor for adapters and glue.
- **Phases:** 32 PR-sized phases, each with a Status field.

## Current progress

- **Done in planning:**
  - The owner was grilled on every design branch: four rounds, plus a round after the research.
  - Research is in `docs/research/`:
    - `step-catalogue.md`: every step in the existing `ship.sh` scripts, with file:line references.
    - `official-docs.md`: App Store Connect, Play, MCP, macOS, Shorebird and Firebase facts, verified 2026-10-13.
    - `best-practices.md`: the Dart engine stack.
    - `user-flow-gaps.md`: proposed defaults, now folded into the plan.
  - The plan was reviewed by three agents (simplicity, VGV and scope splitting), and their findings are applied.
  - The brainstorm is in `docs/brainstorm/`.
- **Design:** `docs/design/PRODUCT.md` (the product brief) and four prompts in `docs/design/prompts/`. The owner runs those in a separate design tool.
  - The results (visual direction, `tokens.json`, screen concepts, icon) come back into `docs/design/`.
  - They gate only Phases 15–17 (the desktop UI) and 18b–18c (icon, Sparkle).
- **Repo state:** this folder is a fresh `git init` on `main` with no commits. No GitHub repo exists yet.
- **No code has been written.** Every phase has `Status: Not started`.

## What worked

- **Ground rules:**
  - Put every fact-finding task in a subagent. Put every decision to the owner as a numbered question with a recommended answer that a "yes" accepts.
  - Verify claims against primary sources. For example, Shorebird `login:ci` tokens stopped working on 2026-10-01, and `dart compile exe` does not run build hooks.
- **Reference code to port from** (read it, never edit it):
  - `~/dev/mobile_apps/Mataa/mataa_new_app/scripts/ship.sh` and `scripts/lib/release.sh`
  - `~/dev/mobile_apps/Mataa/mataa_captain/scripts/ship.sh`
  - `~/dev/oneavant/mobile-apps/scripts/ship.sh` and `scripts/lib/common.sh`

## What didn't work / watch out

- **`dart compile exe`** fails when the `sqlite3` build hook is present. Use `dart build cli`, which outputs a bundle folder rather than a single file. Cross-compiling to Linux is unverified; that's ADR 0001.
- **Melos 8** has no `melos.yaml`. Its config goes under `melos:` in the root `pubspec.yaml`, and it requires pub workspaces.
- **`auto_updater`** is effectively unmaintained. Embed Sparkle directly through `packages/xp_macos_services`.
- **`dart_mcp`** 0.5.2 supports stdio only, which is enough for 1.0 (D-12). Don't take the git dependency on 0.6.0-wip.
- **Keychain secrets:** `security add-generic-password -w <secret>` exposes the secret in `ps`. Use `security -i` over stdin.
- **ASC status:** `appStoreState` is deprecated. Use `appVersionState`.
- **Play:** `edits.commit` defaults to cancelling an in-flight review. Always pass `changesInReviewBehavior=ERROR_IF_IN_REVIEW`.
- **altool** can exit 0 after a rejection, so parse its output. See `mataa_new_app/scripts/ship.sh:752-762`.
- **Safety:** never run destructive git commands in the Mataa or oneavant repos. They are reference only. XPath tests use fixture repos under `tool/e2e/fixtures/`.

## Next steps

1. Run the phases in order with `/vgv-wingspan:build docs/plan/2026-10-13-feat-xpath-release-tool-plan.md`.
   - `/build` executes one phase per context window and sets `Status: Done` after committing.
   - Commit on a feature branch per phase or sub-phase: `feat/phase-0-spikes`, `feat/phase-1-workspace`, and so on.
   - Merge locally into `main` with squash.
2. **Phase 0 first:** four spikes, each recorded as an ADR in `docs/adr/`. ADRs 0001 and 0002 decide the shape of Phases 1 and 3.
3. **Phase 1 creates the GitHub repo.** It's private, at `AbdurahmanAlmehdi/x-path`. **Ask the owner before creating it and before the first push.**
4. Stop and ask the owner when:
   - a phase needs a decision the plan does not cover;
   - an ADR contradicts a D-xx decision;
   - anything would touch the Mataa or oneavant repos;
   - Phase 15 starts and `docs/design/tokens.json` or a chosen direction does not exist yet. In that case, skip ahead to the next non-UI phase.
5. **Prerequisites the owner provides later:**
   - a Developer ID Application certificate on team AFBD5TBR5U (before Phase 18b);
   - API keys and service accounts (before Phase 19).
6. Keep this file updated at the end of each session: progress, surprises, next phase.
