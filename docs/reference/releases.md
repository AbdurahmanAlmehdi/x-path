# Releases, notifications and housekeeping

The release state machine and its endpoints, notifications and housekeeping. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## Releases

A **release** is one flavor of an app going to the stores (D-17). The engine creates it when a workflow that cuts
a release branch (`git.releaseBranch`, so `prod-release`) is dispatched, one per flavor of the run, and follows it
to the end. `packages/xp_engine/lib/src/releases` has the logic, `apps/xpd/lib/src/api/releases` the endpoints.

```text
draft -> building -> uploaded -> in_review -> approved -> live -> merged
                                    |
                                    +-> rejected -> building (a new build of the same version)
                       any state that is not over -> abandoned
```

- **How it moves.** `ReleaseStateMachine` lists the allowed moves (a store that is quick, or an internal Play
  track, may take `uploaded` straight to `approved` or `live`). The service reads the steps of the jobs of the
  release (`ReleaseService.sync`): `building` once a build step started, `uploaded` once every store the release
  targets (`upload.appStore` is Apple, `upload.play` is Play) has its upload, and the branch, tag and pull request
  as their steps succeed. After that the **stores** decide, each with its own status (`pending`, `uploaded`,
  `in_review`, `rejected`, `approved`, `live`; kept in `store_status`): the release is `rejected` if any store is,
  else as far along as the slowest store (`in_review` while either reviews, `live` only when every store targeted
  is). A status only moves forward, and a rejection only before the approval. Reading a release brings it up to
  date with its jobs, and `ReleaseWatcher` does the same when a job or step event arrives.
- **Asking the stores** (D-14, D-15). Apple: App Store Connect `appVersionState` of the version with the API key
  (`IN_REVIEW`/`WAITING_FOR_REVIEW` are in review, `REJECTED`/`METADATA_REJECTED`/`INVALID_BINARY`/
  `DEVELOPER_REJECTED` rejected, `PENDING_*`/`ACCEPTED` approved, `READY_FOR_DISTRIBUTION` live); an Apple ID
  flavor has no key, so the iTunes lookup says the version is live when it is on sale in the app's storefront and
  approval is the owner's button. Play: `tracks.releases.list`, the release that holds the version code
  (`IN_REVIEW`, `NOT_APPROVED`, `APPROVED_NOT_PUBLISHED`, `PUBLISHED`); without a service account the owner presses
  "Play: live". `ReleaseStatusPoller` asks a store at most every ten minutes (the `checked_at` of its status is the
  cache, so a restart keeps it), also a store that fails, and a store that cannot be read keeps its status and says
  why in `note`. `ReleaseWatcher` checks what is due every minute; `POST /releases/{id}/refresh` asks at once.
- **By hand.** `POST /releases/{id}/stores/{apple|play}/status` takes `approved` or `live` for Apple and `live`
  for Play, once the store has the build. Because a status moves the release toward the merge of its pull request,
  it and `abandon` are for `app` and `cli` tokens (`403` for `mcp` and `runner`, D-13). A `runner` token reaches no
  release route at all (ADR 0011).
- **New build, same version.** After a rejection `POST /releases/{id}/builds` dispatches the workflow that made
  the release again, on its release branch, with the same version and a new build number (D-11, never reused) and
  the inputs of the first dispatch (`DispatchRequest.release` links the run; a workflow reads it as `release`, and
  `prod-release` skips the check that the version shipped before when it is set). The release goes back to
  `building`, the stores to `pending`; App Store Connect keeps reporting `REJECTED` for the version until the new
  build is submitted, so that reading is ignored until it changes. The new build is tagged and pushed (the branch
  moves forward only) and reuses the open pull request.
- **The pull request is opened after the push**, by the `github.createPr` step of `prod-release` (the release
  branch is not on GitHub before the gated push, so opening it when the release starts is not possible). An open
  pull request for the same branches is reused.
- **The merge** is enabled once every store targeted is live (`mergeEnabled`). `POST /releases/{id}/merge` runs the
  built-in `release-merge` workflow on the release branch; its `gate: merge` binds the approval to the project,
  the commit and `x.y.z+build`, so it waits for an `app` or `cli` token to approve it (an `mcp` token gets the pending
  approval and can poll, never approve). `github.mergePr` then merges with a **merge commit** (ADR 0007: it calls
  `mergePullRequest` without a method, and the e2e asserts `merge_method: merge`), only when the release is `live`
  and only the commit that was tagged (`sha` is sent, so a push to the branch since is refused with GitHub's
  `409`). The release is `merged` when the step succeeded. A merge run that ends without merging (a denied gate, a
  GitHub error) frees the merge to be asked for again, and asking while a run is under way answers with it.

| Route | What it does |
|---|---|
| `GET /releases[?project=&app=&state=]` | The releases, newest first, each brought up to date. |
| `GET /releases/{id}` | One release: state, `version`, `build`, `builds`, the status in each `stores`, `branch`, `tag`, `headSha`, `prNumber`, `prUrl`, `mergeEnabled`, `mergeCommit`. |
| `POST /releases/{id}/refresh` | Asks the stores now (bypasses the ten-minute cache). Any token but a `runner` one (ADR 0011). |
| `POST /releases/{id}/stores/{store}/status` | `{"state": "approved" or "live"}`. `app` and `cli` tokens; `409` when the store has no build yet or is past that status. |
| `POST /releases/{id}/builds` | New build, same version. `202` with the run; `409` unless the release is `rejected`. |
| `POST /releases/{id}/merge` | Request the merge. `202` with the run, which waits for approval; `409` unless the release is `live` with a pull request. |
| `POST /releases/{id}/rollout` | `{"store", "action", "userFraction"}`: pause, resume or complete Apple's phased release; set the `fraction`, `halt` or `complete` Google Play's staged rollout. `202` with the run of `release-rollout`, which waits at `gate: rollout`; `400` for a change the store cannot make, `409` before the stores approved the release. |
| `GET /releases/{id}/history` | What happened to the release, oldest first: its dispatch and builds, each change in a store (with the device that set a status by hand), the merge, the rollout changes and the Shorebird patches with their promotions and rollbacks. A `shorebird-patch` run of a released version is linked to its release. |
| `PUT /releases/{id}/texts` | `{"whatsNew", "whatToTest"}`. `app` and `cli` tokens. An upload reads them when it runs: `whatsNew` goes to Google Play (`en-US`), `whatToTest` (else `whatsNew`) to Firebase testers, unless the step has release notes of its own. |
| `POST /releases/{id}/patches/{number}/{promote\|rollback}` | Moves a Shorebird patch XPath published. `202` with the run of `shorebird-track`, which waits at `gate: prod_patch`; `400` for a patch the release has none of. |
| `POST /releases/{id}/abandon` | `{"reason"}` optional. `app` and `cli` tokens; cancels a run that still builds it. |

`release.created`, `release.state_changed` and `release.store_changed` go on `/events`.

## Notifications and housekeeping

`packages/xp_engine/lib/src/notify` tells the owner what matters (D-22); `.../housekeeping` keeps the disk in
check (D-22, D-24). The endpoints are in `apps/xpd/lib/src/api/storage`.

### Notifications

`Notifier` listens to the event log. `NoticeFactory` decides which events are worth telling: a **production job**
(a job of a release, or of a run that holds the project lock) that failed or succeeded, an approval that was
requested, decided or expired, a release that was rejected, approved, went live or was merged, a credential that
expired, and secrets that are locked (D-10, from `SecretStore.statusChanges`). Each becomes

- a `notification.raised` event (`kind`, `level`, `title`, `body`, and the project, release, job or approval it
  is about), which the macOS app shows as a notification (Phase 16b; the engine only raises the event); and
- a Slack message to the webhook of a `slack` credential assigned to a flavor of the project, if it has one (the webhook URL comes from
  the secret store, `HttpSlackWebhook` posts it with `package:http`). The text goes through the secret masker and
  is cut to 600 characters. A message is tried again after 1, 5 and 30 seconds (or as long as Slack's
  `Retry-After` says, at most a minute); one that still fails is reported on stderr and dropped. Messages of one
  project go out in the order of the events. Locked secrets go to the app only: the webhook is one of the secrets
  that cannot be read then.

The same notice (same `kind` and subject) within 15 minutes is told once, so a flapping state does not repeat,
and at most 20 messages a minute go to Slack. The app is told even when Slack is not.

**`min_version_*` reminder.** Raising `min_version_android` and `min_version_ios` in Firebase Remote Config is only
right once the new version is approved *and available* in that store (`mataa_new_app/docs/RELEASING.md`). When a
store reports a release `live`, a `min_version_reminder` notification names the variable of that store
(`min_version_ios` for the App Store, `min_version_android` for Google Play) and the version. XPath does not know
whether a release is a forced update, so the text says "if this is a forced update"; it is a reminder only and
calls no remote-config API.

**Release notes.** `GET /releases/{id}/notes` lists the commits (merge commits and XPath's own
`chore(release)` version commits left out) between the previous release tag and the commit of the release, from the
engine's mirror (it does not fetch). The previous tag is the newest non-patch tag of the same app and flavor, by the
project's release model, with a lower version; a first release lists its latest 100 commits. Commits are grouped by
conventional-commit type (breaking changes, features, fixes, performance, refactoring, documentation, other), and
the response has the groups plus the text twice: Slack `mrkdwn` (`*bold*`, `<url|Full changelog>`, `&`, `<` and `>`
escaped) and WhatsApp text (`*bold*`, the link as plain text). `409` while the release has no commit yet.

### Housekeeping

`HousekeepingPlanner` decides, `HousekeepingService` reports and does it.

| Category | What goes | What stays |
|---|---|---|
| `artifacts` | The files of builds past the newest `keepPerFlavor` (5 unless set) of each flavor of each app. A build is a run, so one release that builds iOS and Android and records a manifest is one build. | Pinned artifacts; every artifact of a release that is **not over** (`draft`, `building`, `uploaded`, `in_review`, `rejected`, `approved`, `live`), also those of the runs that built or merge it; artifacts of jobs that have not finished. |
| `logs` | The log folder and the record of jobs that finished more than `logDays` (90, D-24) ago. | The record of a job that a release not over needs, whose test run is a **current baseline** (the job row cascades to its test run, D-21), or that still has an artifact. |
| `worktrees` | Worktrees of jobs that succeeded or were cancelled, of failed jobs after 7 days, and of no job at all. | Worktrees of jobs that have not finished, of failed jobs for a week (they can be resumed) and of failed jobs of a release not over. |
| `mirrors` | Mirrors of repositories that are no longer projects (removing a project leaves its mirror, D-05). | Mirrors of projects. |
| `flutter` | SDKs of the cache that no app pins in `.fvmrc`, no Shorebird release was built with (D-20) and no unfinished job uses. | The others. |

- **Daily.** `HousekeepingSchedule` prunes the logs (and the records that nothing needs) at the start when the last
  pruning was a day ago or never, then every 24 hours, on the `Clock`. Nothing else is deleted by itself: the
  owner presses "free up space".
- **Retention settings** are kept in the `housekeeping_setting` table (migration 12): `GET`/`PUT
  /storage/retention` (`keepPerFlavor` and `logDays`, both at least 1).
- **Who may delete.** Deleting is a gated action (D-13), but a gate binds an approval to one project, a commit and
  a version, and housekeeping spans every project. So it is treated like `abandon` and the store statuses: only
  `app` and `cli` tokens may delete (`"dryRun": false`) or change the retention, and that token is the owner
  approving; `mcp` tokens get `403` and may only read the report and dry-run, and `runner` tokens reach nothing here (ADR 0011).

| Route | What it does |
|---|---|
| `GET /storage` | The report: per category the bytes held and the bytes that would be freed, and the artifacts by app and flavor. Deletes nothing. |
| `POST /storage/free` | `{"dryRun": true, "categories": [...]}`, both optional. A dry run (the default) says what would be freed; `"dryRun": false` deletes (`app`/`cli` tokens), artifacts first, and answers what was freed and what could not be. |
| `GET /storage/retention`, `PUT /storage/retention` | `{"keepPerFlavor", "logDays"}`. `PUT` is for `app` and `cli` tokens. |
