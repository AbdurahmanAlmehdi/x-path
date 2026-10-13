Using the XPath design system ([link to the design system artifact]) and the [DIRECTION NAME] direction I chose on the earlier canvas ([link to the visual directions canvas]), design the three most important screens, each as structurally different concepts, so I can see how the product feels in practice and pick a layout before we build. I've attached PRODUCT.md (the product, the data the engine really returns, the sample data).

## Ground rules

- macOS app built in Flutter, 1440×900, light mode for everything plus dark mode for the concept you recommend on each screen.
- Design within the data in PRODUCT.md §7. If a screen would really benefit from something the engine does not return, draw it as a clearly labelled optional variant, never in the main version.
- Use the status tokens, icons, labels and agent marker from the design system. If you need a new token or component, list it at the end instead of inventing it inline.
- One hero per screen: the large style is for the thing the user came for (a job's result, a release's state, a pending approval), not decoration.
- Use the sample data in PRODUCT.md §9 so every number agrees across screens.
- No emoji, no gradient washes, no illustrations.

## The screens

For each screen draw **3 structurally different concepts** (different layouts and information hierarchy, not recolours), say which you'd choose and why, and cite the real tools that inspired each (Xcode, Railway, GitHub Actions, Vercel, Linear, Buildkite, Codemagic, Bitrise, Expo EAS, App Store Connect, Play Console).

### 1. Project overview: `mataa_new_app`

Mid-release state: prod release 5.4.1 (3283) job running (iOS building on This Mac, Android done on linux-builder-01), App Store "waiting for review", Play "in review", Claude Code's pending App Store submission approval, dev flavor at 5.5.0 (3284), live versions iOS 5.3.6 and Android 5.3.7 with Shorebird patches p1 and p2 on 5.3.7, last test run 0 new failures.

Concept ideas to push against (use, change or replace): a flavor matrix (rows = flavors, columns = local / testing / live per platform); a Railway-like canvas of apps and flavors with live activity; a timeline-first view with the active release on top.

Also show the same screen for a quiet project (nothing running, everything live) in your chosen concept.

### 2. Job view: Prod release 5.4.1 (3283)

Stages Preflight → Build → Upload → Record; Build has parallel iOS (This Mac, running 6:12) and Android (linux-builder-01, done 4:55); Upload is waiting for approval. Live log of the iOS job following tail.

Concept ideas: GitHub Actions-style graph on top with the log below; Xcode-style step navigator on the left with the log as the main pane; a single vertical timeline where steps expand inline into their logs.

Then, in your chosen concept, small frames for: a failed step (the altool "train closed" rejection, with the log scrolled to the error and a suggested fix), an interrupted job after the engine restarted (resume from step), and cancel confirmation.

### 3. Release detail: `mataa_new_app` 5.4.1 (3283)

App Store lane, Play lane, timeline (built, uploaded, submitted, in review...), release notes (with "copy for Slack" and "copy for WhatsApp"), the forced-update note and "raise min_version after approval" reminder, the release PR, and the Merge button.

Concept ideas: two parallel swimlanes; a single merged timeline with lane chips; a checklist-style "what's left before Merge".

Then, in your chosen concept, small frames for: both lanes live (Merge awake), App Store rejected (with "new build, same version"), and a flavor with no App Store Connect API key (lane shows only the public live version plus "Mark approved").

## Small frames (chosen concept only, no variants)

- The approval as it appears in the approvals inbox and as a macOS notification.
- The menu bar extra with one running job and one pending approval.
- The dispatch sheet filled in for a prod release.

## What I want back

- For each screen, the concept you'd choose and why.
- The new tokens or components you had to add to the design system.
- Anything about the product that the designs made you question.
