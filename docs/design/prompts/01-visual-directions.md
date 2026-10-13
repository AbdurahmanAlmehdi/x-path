I'm designing XPath, a new open-source Mac app for teams that ship Flutter apps. It takes an app from "code on a branch" to "live in the App Store and Google Play": it builds iOS and Android, runs the tests, signs, uploads to both stores and to testers, tags the release, watches Apple and Google review it, and merges the release into `main` once both are live. A background engine does the work on the developer's own machines (a MacBook, a Mac mini, a Linux box); the Mac app is how people see and drive it. AI agents can drive it too, but risky actions wait for a human to approve them in the app.

I've attached PRODUCT.md, which describes exactly what it does, its vocabulary and statuses, the data the engine returns, and sample data. Read it fully first: it's the source of truth.

The feeling I'm after: **Xcode meets Railway meets GitHub Actions.** Xcode's native precision and quiet confidence; Railway's clarity about what is running where and its calm, spacious canvas; GitHub Actions' readable pipeline of jobs and steps with a live log you can trust.

First I need visual directions, then a design system, then concepts for the key screens. Work in the steps below and stop where I ask you to.

## Research first

Study real tools before proposing anything, and cite the specific screens that informed each decision. Look at patterns, not just products: pipeline / workflow run graphs, live log viewers, deployment timelines, environment and service canvases, release and review status, approval prompts, runner or machine lists, command palettes, Mac sidebars and toolbars, menu bar extras.

Start with: Xcode (Organizer, Report navigator, build log, Xcode Cloud), Railway (project canvas, deployments, logs), GitHub Actions (workflow run graph, job log), Vercel (deployments), Linear (density, keyboard, command palette), Raycast, Tower or Fork (Mac git clients), Expo EAS, Codemagic, Bitrise, Buildkite, Tailscale (machine list), Docker Desktop, App Store Connect and Play Console (the store states this app mirrors). If you can't browse, say so in one line and work from your own knowledge of them.

## References I'm attaching

[Screenshot 1: what I like about it]
[Screenshot 2: ...]
[Screenshot 3: ...]

Take the direction from these, not the content. Tell me what you borrowed from each.

## The key screens (for later steps; read now so the directions fit them)

The content listed for each screen is a starting brief, not a spec. Use UX best practice and your research to decide what belongs on each screen: add what's missing, cut or move what doesn't earn its place, and tell me what you changed and why.

Non-negotiables:
- **What is running, where, and what is waiting on me** is answerable in under three seconds from anywhere in the app.
- Status is unmistakable wherever a job, step, release, store lane, runner or approval appears: a label and an icon, never colour alone (PRODUCT.md §5).
- Anything an AI agent started or requested is visibly marked as agent-originated.
- Approvals always show exactly what will happen: action, app, version, commit. Approve is never one stray click away.
- Logs are first-class: monospace, searchable, fast, readable for long sessions.
- Keyboard-first: every primary action has a shortcut; Cmd-K reaches everything.
- Design within the data in PRODUCT.md §7.

Screens:
1. **Project overview.** Each app and flavor with local / testing / live versions, the active release, recent jobs. Decide what earns the top of the window for a project mid-release versus a quiet one.
2. **Job view.** Stages, parallel jobs on different runners, steps, the live log, artifacts, cancel / re-run / resume from step.
3. **Release detail.** App Store lane and Play lane side by side, timeline, release notes, approvals, and the Merge button that only wakes up when both lanes are live; the "raise minimum version" reminder for forced updates.
4. Supporting: dispatch sheet, approvals inbox, runners, tests vs baseline, workflow builder with YAML, storage, onboarding and scan review, menu bar extra.

Use the sample data in PRODUCT.md §9 (mataa_new_app 5.4.1 (3283) in review on both stores, the running prod-release job on This Mac and linux-builder-01, Claude Code's pending App Store submission, 27 baseline test failures) so the screens feel real and the numbers agree.

## Step 1: visual directions (then STOP)

Propose 3 clearly different visual directions. They should differ in structure and personality, not just colour. For each one:
- a name and a one-line idea;
- palette, typography (a UI face and a monospace face; say why), iconography and shape language;
- how it uses the Mac: sidebar, toolbar, translucency, window chrome;
- the **Project overview** drawn in that direction at 1440×900, in two states: a quiet project (last release live, nothing running) and `mataa_new_app` mid-release (prod job running, App Store waiting for review, Play in review, one pending agent approval). Show one of them in dark mode.

Base each direction on patterns from the tools above and say which tool inspired what. Then stop and let me choose.

Constraints for every direction:
- Trustworthy and precise: people ship production apps with it. Calm when things are fine, impossible to miss when something needs a human. Not a neon "hacker" dashboard, not a marketing site.
- Dense enough for an expert, never cramped. Text contrast at least 4.5:1.
- Light and dark mode, both first-class.
- Buildable in Flutter for macOS (custom widgets are fine; no web views, no effects Flutter can't draw).
- No emoji in the interface, no gradient washes, no stock illustrations, no rocket ships.
- The logo and icon come later; don't depend on them. Leave a slot for a small symbol in the sidebar.

Be opinionated. Tell me which direction you'd pick and why.
