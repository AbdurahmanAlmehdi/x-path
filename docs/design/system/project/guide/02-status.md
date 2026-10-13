# Status

Every status in the product brief has a label, a Phosphor icon and a colour pair. Statuses that mean the same thing to the user share a pair:

| Pair | Means | Shared by |
|---|---|---|
| `neutral` | Nothing to do, nothing wrong | queued, waiting for runner, cancelled, skipped, draft, uploaded, processing, waiting for review, unknown, expired approval, offline runner, Firebase uploaded |
| `info` | Something is moving | running, building, in review (both stores), runner busy, runner updating, scan info |
| `attention` | A human must act | waiting for approval, approval pending, ready to submit, not sent for review, pending developer release, approved not published, secrets locked |
| `positive` | Done and good | succeeded, approved, live, ready for sale, published, phased rollout, rolling out, distributed, verified, runner idle, engine connected |
| `negative` | Broken or refused | failed, rejected, not approved, denied, lost mid-job, unreachable, scan error, credential expired or rejected |
| `caution` | Degraded, not blocked | interrupted, reconnecting, credential expiring or missing, scan warning |
| `merged` | Terminal success | release merged |

Icons separate statuses that share a pair (queued `circle-dashed`, waiting `hourglass-medium`, cancelled `stop-circle`, skipped `skip-forward-circle`) so a colour-blind reader, or a glance at a greyscale screenshot, still tells them apart. Lightness differs between `positive`, `negative` and `attention` on-container colours in both themes, and green/red are never the only difference.

## Every status

| Group | Status | Label | Pair | Icon (Phosphor) | Moves |
|---|---|---|---|---|---|
| Job and step | `job.queued` | Queued | `neutral` | `circle-dashed` | — |
| Job and step | `job.waiting-runner` | Waiting for runner | `neutral` | `hourglass-medium` | — |
| Job and step | `job.waiting-approval` | Waiting for approval | `attention` | `hand-palm` | — |
| Job and step | `job.running` | Running | `info` | `circle-notch` | spin |
| Job and step | `job.succeeded` | Succeeded | `positive` | `check-circle` | — |
| Job and step | `job.failed` | Failed | `negative` | `x-circle` | — |
| Job and step | `job.cancelled` | Cancelled | `neutral` | `stop-circle` | — |
| Job and step | `job.skipped` | Skipped · already done | `neutral` | `skip-forward-circle` | — |
| Job and step | `job.interrupted` | Interrupted | `caution` | `pause-circle` | — |
| Release | `release.draft` | Draft | `neutral` | `pencil-simple` | — |
| Release | `release.building` | Building | `info` | `circle-notch` | spin |
| Release | `release.uploaded` | Uploaded | `neutral` | `upload-simple` | — |
| Release | `release.in-review` | In review | `info` | `eye` | — |
| Release | `release.rejected` | Rejected | `negative` | `x-circle` | — |
| Release | `release.approved` | Approved | `positive` | `check` | — |
| Release | `release.live` | Live | `positive` | `radio-button` | — |
| Release | `release.merged` | Merged | `merged` | `git-merge` | — |
| Release | `release.abandoned` | Abandoned | `neutral` | `archive` | — |
| App Store lane | `appstore.processing` | Processing | `neutral` | `hourglass-medium` | — |
| App Store lane | `appstore.ready-to-submit` | Ready to submit | `attention` | `paper-plane-tilt` | — |
| App Store lane | `appstore.waiting-review` | Waiting for review | `neutral` | `clock` | — |
| App Store lane | `appstore.in-review` | In review | `info` | `eye` | — |
| App Store lane | `appstore.pending-release` | Pending developer release | `attention` | `hand-palm` | — |
| App Store lane | `appstore.rejected` | Rejected | `negative` | `x-circle` | — |
| App Store lane | `appstore.live` | Ready for sale | `positive` | `radio-button` | — |
| App Store lane | `appstore.phased` | Phased rollout · day 3 of 7 | `positive` | `radio-button` | — |
| App Store lane | `appstore.unknown` | Unknown · live 5.3.6 | `neutral` | `question` | — |
| Google Play lane | `play.draft` | Draft | `neutral` | `pencil-simple` | — |
| Google Play lane | `play.not-sent` | Not sent for review | `attention` | `paper-plane-tilt` | — |
| Google Play lane | `play.in-review` | In review | `info` | `eye` | — |
| Google Play lane | `play.approved-unpublished` | Approved · not published | `attention` | `hand-palm` | — |
| Google Play lane | `play.not-approved` | Not approved | `negative` | `x-circle` | — |
| Google Play lane | `play.live` | Published | `positive` | `radio-button` | — |
| Google Play lane | `play.rolling-out` | Rolling out · 20% | `positive` | `radio-button` | — |
| Google Play lane | `play.unknown` | Unknown · live 5.3.7 | `neutral` | `question` | — |
| Firebase (testers) | `firebase.uploaded` | Uploaded | `neutral` | `upload-simple` | — |
| Firebase (testers) | `firebase.distributed` | Distributed · 2 groups | `positive` | `users-three` | — |
| Approval | `approval.pending` | Pending | `attention` | `hand-palm` | — |
| Approval | `approval.approved` | Approved | `positive` | `check` | — |
| Approval | `approval.denied` | Denied | `negative` | `prohibit` | — |
| Approval | `approval.expired` | Expired | `neutral` | `clock-countdown` | — |
| Runner | `runner.idle` | Online · idle | `positive` | `check-circle` | — |
| Runner | `runner.busy` | Online · busy 2/3 | `info` | `circle-notch` | spin |
| Runner | `runner.offline` | Offline | `neutral` | `circle-dashed` | — |
| Runner | `runner.lost` | Lost mid-job | `negative` | `warning-circle` | — |
| Runner | `runner.updating` | Updating | `info` | `arrows-clockwise` | turn |
| Engine connection | `engine.connected` | Connected | `positive` | `plugs-connected` | — |
| Engine connection | `engine.reconnecting` | Reconnecting | `caution` | `arrows-clockwise` | turn |
| Engine connection | `engine.unreachable` | Unreachable · cached | `negative` | `cloud-slash` | — |
| Engine connection | `engine.secrets-locked` | Secrets locked | `attention` | `lock-simple` | — |
| Scan finding | `scan.error` | Error | `negative` | `x-circle` | — |
| Scan finding | `scan.warning` | Warning | `caution` | `warning` | — |
| Scan finding | `scan.info` | Info | `info` | `info` | — |
| Credential | `credential.verified` | Verified | `positive` | `seal-check` | — |
| Credential | `credential.expiring` | Expiring in 12 days | `caution` | `clock-countdown` | — |
| Credential | `credential.expired` | Expired | `negative` | `seal-warning` | — |
| Credential | `credential.missing` | Missing | `caution` | `key` | — |

## Running treatment

The running arc (`circle-notch`) turns once per `motion.duration.spin` (1 s, linear). A running pipeline node also gets a 1px inset `color.info.default` ring (2px border in total) and shows elapsed time in `type.code`, updated every second. `arrows-clockwise` (reconnecting, updating) turns once per `motion.duration.pulse` (1.6 s) so the two never read as the same thing. **Nothing else animates**: external waits (in review, waiting for review, processing) are still, because XPath is not doing that work.

**Reduce Motion fallback:** the arc stops at three quarters with a filled centre dot (the icon in Running is drawn that way already); the elapsed timer keeps counting (a number changing is not motion); `arrows-clockwise` stays still. Status changes swap instantly instead of crossfading.
