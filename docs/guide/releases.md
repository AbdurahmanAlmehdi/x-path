# Releases

A release is one production flavor of an app going to the App Store and Google Play. XPath
creates it when you dispatch `prod-release` and follows it through store review to the merge of
its pull request. This page walks through one release, and what you can do on the way.

## Dispatch a production release

Before the first release, give the production flavor its credentials (a `play_sa` service account
for Google Play, an `asc_key` or `apple_id` for the App Store) and its App Store Connect app id. See
[Credentials](credentials.md) and [Projects](projects.md).

In the app, press ⌘N and pick `prod-release`. From the command line, look first, then dispatch:

```sh
xp dispatch acme/app prod-release --flavor prod --platform android --platform ios \
  --bump patch --dry-run
xp dispatch acme/app prod-release --flavor prod --platform android --platform ios \
  --bump patch --input 'playTrack=internal'
```

Its inputs are `appleAppIds`, `playTrack` (default `internal`), `notes`, `firebaseAppIds`,
`testerGroups`, `exportOptionsPlist` and `dartDefineFile`. Android goes to Google Play when the
flavor has a `play_sa` credential, iOS to App Store Connect when it has an Apple app id.

The run bumps the version, then stops twice for you:

1. `prod_release`, before it cuts the branch `release/<x.y.z>`.
2. `push`, before the branch leaves the machine. This approval also covers the tag push at the end.

Then it checks, builds, uploads, tags `v<x.y.z>+<build>`, pushes the tag and opens the release pull
request. `prod-release` locks the project: a second release or patch queues behind it. See
[Approvals](approvals.md).

## Release states

The run creates one release per flavor:

```text
draft -> building -> uploaded -> in_review -> approved -> live -> merged
                                    |
                                    +-> rejected -> building (a new build of the same version)
                       any state that is not over -> abandoned
```

- `building` once a build step started; `uploaded` once every store the release targets has its
  upload.
- After that the stores decide. The release is as far along as its slowest store, and `rejected`
  if any store rejected it.
- `merged` and `abandoned` are the end.

```sh
xp releases list --project acme/app --state in_review
xp releases show rel_...      # state, version, build, branch, tag, pull request, each store
```

## Follow the stores

The release page has an App Store lane and a Google Play lane. Each store has its own status:
`pending`, `uploaded`, `in_review`, `rejected`, `approved` or `live`.

- With an App Store Connect API key, XPath reads the review from App Store Connect. With an Apple
  ID it can only see when the version is on sale, so marking it approved is up to you.
- With a Play service account, XPath reads the release from Google Play.
- XPath asks each store at most every ten minutes. Press Refresh, or run
  `xp releases refresh rel_...`, to ask now.

## Mark a store by hand

When XPath cannot read a store (no API key or no service account for the flavor), the lane offers
"Mark approved" and "Mark live". From the command line:

```sh
xp releases status rel_... apple approved
xp releases status rel_... apple live
xp releases status rel_... play live
```

Apple takes `approved` or `live`, Google Play `live`, and only once the store has the build. A mark
cannot be taken back, and only an `app` or `cli` token may set one.

## Build again after a rejection

When a store rejects the build, fix the problem and start a new build of the same version: "New
build, same version…" in the lane, or:

```sh
xp releases build rel_...
```

It runs the workflow again on the release branch, with the same version and inputs and a new build
number. The release goes back to `building`, the stores to `pending`, and the open pull request is
reused. It works only while the release is `rejected`.

## Change the rollout

Once the stores approved the release (`approved`, `live` or `merged`), you can change how it
reaches users in a store it went to:

- **Apple phased release:** pause, resume or complete (release to all).
- **Google Play staged rollout:** set the share of users, halt or complete.

The store lanes have these controls. From the command line, give one change:

```sh
xp releases rollout rel_... --store apple --pause
xp releases rollout rel_... --store apple --resume
xp releases rollout rel_... --store play --percent 20
xp releases rollout rel_... --store play --halt
xp releases rollout rel_... --store play --complete
```

Each change starts the `release-rollout` workflow, which waits at the `rollout` gate until you
approve it. An agent asks with the MCP tool `request_rollout` and waits for you the same way. A
change the store cannot make is refused with `400`.

## Read the history

The release page shows a timeline. It comes from `GET /releases/{id}/history`: the dispatch and
each build, each change in a store (with the device that set a status by hand), the merge, the
rollout changes and the Shorebird patches with their promotions and rollbacks. The approvals of
the release's runs are in the timeline too.

## Set the store texts

The Store texts panel of the release page has two fields:

- **What's new** goes to Google Play as the release notes (`en-US`).
- **What to test** goes to Firebase App Distribution testers; without it they get What's new.

An upload reads them when it runs, so set them before the upload stage, for example while the run
waits at its first gate. Notes the workflow itself gives win. The API is
`PUT /releases/{id}/texts` with `{"whatsNew": "...", "whatToTest": "..."}`; a blank text clears
it. Only `app` and `cli` tokens may set them.

## Patch a release with Shorebird

For a Shorebird flavor, publish an over-the-air patch to the exact release it applies to:

```sh
xp dispatch acme/app shorebird-patch --flavor prod --platform android \
  --release-version 5.4.1+3283
```

It runs the checks, waits at `prod_patch`, publishes the patch, tags `v<x.y.z>+<build>-p<n>` and
waits at `push` before it pushes the tag. The patch then shows on its release page under
Shorebird patches.

From there, Promote moves a patch to the stable track and Roll back takes it back. Each starts the
`shorebird-track` workflow, which waits at `prod_patch` for your approval. The API is
`POST /releases/{id}/patches/{n}/promote` or `.../rollback`, for a patch XPath published, once the
stores approved the release.

## Merge the release pull request

Once every store the release went to is live, Merge opens beside the release. Or:

```sh
xp releases merge rel_...
```

It starts `release-merge`, which waits at the `merge` gate. Approved, it merges the pull request
with a merge commit, and only the commit that was tagged: if someone pushed to the release branch
since, GitHub refuses. The release is then `merged`. If the merge run ends without merging (denied,
expired or a GitHub error), you can ask for the merge again.

When a store reports the release live, XPath also reminds you to raise `min_version_ios` or
`min_version_android` in Firebase Remote Config if this is a forced update. It changes nothing
itself.

## Share the release notes

XPath lists the commits since the previous release tag of the same app and flavor, grouped by
conventional-commit type, without merge commits and its own version commits. They are ready once
the release is tagged.

```sh
xp releases notes rel_...                     # Slack text
xp releases notes rel_... --format whatsapp   # WhatsApp text
```

The release page has "Copy for Slack" and "Copy for WhatsApp".

## Abandon a release

A release you will not finish can be given up while it is not over:

```sh
xp releases abandon rel_... --reason "Shipped the fix in 5.4.2 instead"
```

A run that still builds it is cancelled. Only an `app` or `cli` token may abandon a release. Its
artifacts are then no longer kept back when you [free up space](storage.md).

More: [Releases, notifications and housekeeping](../reference/releases.md) and
[the store reference](../reference/stores.md).
