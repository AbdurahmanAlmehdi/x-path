# The built-in workflows

From the engine's built-in workflow documents (`packages/xp_engine/lib/src/workflows`). Every
project gets these the
first time its workflows are listed, and a new version when the engine ships another document.
They cannot be edited or deleted; read the current YAML with
`xp workflows show <project> <name>` and copy it.

Each one keeps the engine-only steps (guards, gates, uploads, tag, pushes) out of the job that
builds, so the build can be leased to a runner (ADR 0010).

## `dev-build`

No lock: as many run at once as the slots allow. Builds the dev flavors and sends them to testers.

| Stage | Job | Matrix | Steps |
|---|---|---|---|
| `check` | `check` (engine) | platform x flavor | `git.checkout`; `guard` with `[source, credentials]` |
| `build` | `build` (runner-eligible) | platform x flavor | `git.checkout`; `version.bump`; `build.android` (`artifact: apk`) if android; `build.ios` if ios; `record.manifest` |
| `upload` | `upload` (engine) | platform x flavor, only cells with an app id | `upload.firebase` for android with `inputs.firebaseAppIds[flavor.name].android`, else `flavor.firebaseAppId.android`; `upload.appStore` for ios with `inputs.appleAppIds[flavor.name]`, else `flavor.appleAppId`; both `artifactsFrom: build` |

Inputs: `firebaseAppIds` (by flavor and platform, `{dev: {android: "1:..."}}`), `testerGroups`
(default `[]`), `notes` (default `""`), `appleAppIds` (by flavor, `{dev: "1234567890"}`),
`exportOptionsPlist` (default `ios/ExportOptions.plist`), `dartDefineFile`.

## `prod-release`

`lock: project`. Releases a production flavor; a run of it is a release.

| Stage | Job | Matrix | Steps |
|---|---|---|---|
| `prepare` | `prepare` (engine) | flavor | `git.checkout`; `guard [source, credentials]`; `version.bump`; `guard [versionSync]`; `guard [newReleaseNumber]` unless `release` (a new build of a rejected release); `git.releaseBranch` behind `gate: prod_release`; `git.push` (`tag: false`) behind `gate: push` |
| `check` | `check` (engine) | platform x flavor | `git.checkout` (`commitFrom: prepare`); `guard [versionSync, buildNumberReuse, credentials]`; `guard [playTargetSdk]` on android; `guard [appStoreTrain]` on ios |
| `build` | `build` (runner-eligible) | platform x flavor | `git.checkout` (`commitFrom: prepare`); `shorebird.release` for a Shorebird flavor, else `build.android` (`artifact: aab`) or `build.ios`, all `obfuscate: true`; `symbols.archive`; `record.manifest` |
| `upload` | `upload` (engine) | platform x flavor, only cells with somewhere to go | `upload.play` if the flavor has a `play_sa` credential (`track: ${{ inputs.playTrack }}`, `releaseNotes: {en-US: ...}`); `upload.firebase` for a Shorebird flavor with a Firebase app id; `upload.appStore` for ios with an Apple app id |
| `finalize` | `tag` (engine) | flavor | `git.checkout` (`commitFrom: prepare`); `git.tag`; `git.push` (`branch: false`) behind `gate: push`; `github.createPr` |

Inputs: `firebaseAppIds`, `testerGroups`, `notes`, `appleAppIds`, `playTrack` (default
`internal`), `exportOptionsPlist`, `dartDefineFile`. The approval of the first `push` covers the
tag push too: it binds to the same project, commit, version and run.

## `release-merge`

One stage `merge`, one job: `github.mergePr` behind `gate: merge`. Started by
`POST /releases/{id}/merge` (`xp releases merge <release>`) once every store the release went to
is live. No project lock.

## `shorebird-patch`

`lock: project`. Dispatch with `releaseVersion` (`x.y.z+build`, never `latest`). Every job runs
only for Shorebird flavors (`if: flavor.shorebird`).

| Stage | Job | Matrix | Steps |
|---|---|---|---|
| `check` | `check` (engine) | platform x flavor | `git.checkout`; `guard [credentials, patchTarget, patchNativeDiff]`; `guard [source]` behind `gate: prod_patch` |
| `patch` | `patch` (runner-eligible) | platform x flavor | `git.checkout`; `shorebird.patch` (`allowNativeDiffs: ${{ inputs.allowNativeDiffs }}`) |
| `finalize` | `tag` (engine) | flavor | `git.checkout`; `git.tag` (`v<x.y.z>+<build>-p<n>`); `git.push` behind `gate: push` |

Inputs: `exportOptionsPlist`, `dartDefineFile`, `allowNativeDiffs` (default `false`).

## `smoke-build`

One stage `build`, one job per flavor (runner-eligible): `git.checkout`; `build.android`
(`artifact: apk`, `keystore: false`). An APK signed with the debug key, from the version in the
pubspec: no credential, no store id, no upload, no build number. The app offers it after the
first scan ("Try an unsigned build"), so a new project sees a green build before signing is set
up. No inputs.

## `test`

One stage `test`, one job `test` (engine, since `test` is engine-only): `git.checkout`; `test`
(`paths`, `tags` from the inputs); `analyze`. Inputs `paths` and `tags`, both default `[]`.
Allocates no build number.
