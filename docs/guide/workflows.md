# Workflows

A workflow is a YAML document that says what XPath builds, tests, uploads and releases. When you
dispatch it, the engine makes a run; its jobs wait until the scheduler starts them on the engine or
on a [runner](runners.md). Every project has a set of built-in workflows, and you can add your own.

## The built-in workflows

Every project gets these the first time you list its workflows. When a new engine ships a newer
document, the project gets it as a new version.

| Workflow | Use it to |
|---|---|
| `dev-build` | Build the dev flavors and send them to testers: Android to Firebase App Distribution, iOS to TestFlight. Several can run at once. |
| `prod-release` | Release a production flavor to the stores. One at a time per project, and it waits for your approval. A run of it is a [release](releases.md). |
| `release-merge` | Merge the pull request of a release. You start it from the release, not by hand. |
| `release-rollout` | Pause, resume or complete Apple's phased release, or change Google Play's staged rollout. Started from the release. |
| `shorebird-patch` | Publish an over-the-air Shorebird patch to a production release. Give it the exact `x.y.z+build` it patches. |
| `shorebird-track` | Promote a Shorebird patch to the stable track, or roll it back. Started from the release. |
| `smoke-build` | Build an APK of each flavor with the debug key: no credential, no upload. For a first green build before signing is set up. |
| `test` | Run the tests against the baseline, then the analyzer. |

`dev-build` uploads Android when the flavor has a Firebase app id (the `firebaseAppIds` input or
its [store ids](projects.md)), and iOS when it has an App Store Connect app id. Without one, it
builds and keeps the artifacts. The [workflows reference](../reference/workflows.md) lists
the stages and steps of each built-in, and `xp workflows show <project> <name>` prints its YAML.

## Dispatch a workflow

In the app, press ⌘N. The sheet picks the workflow, the app, the flavors, the platforms, the ref
and the version bump, and previews each stage's jobs, where each one runs and which gates it stops
at. The button reads "Dispatch N jobs"; Return never dispatches.

From the command line, list the workflows and their inputs first, then dispatch:

```sh
xp workflows list acme/app
xp workflows show acme/app dev-build          # the YAML, with its inputs
xp dispatch acme/app dev-build --flavor dev --platform android --dry-run
xp dispatch acme/app dev-build --flavor dev --platform android \
  --input 'notes=Fixes the login crash' --follow
```

- `--ref` is a branch, tag or commit (the base branch by default). `--app` picks an app by path in
  a monorepo.
- `--flavor` and `--platform` repeat. By default a workflow with `lock: project` runs the
  production flavors and other workflows run the others; an app with one flavor always uses it.
- `--bump major|minor|patch|keep` or `--version x.y.z` sets the version. `--release-version
  x.y.z+build` names the release a patch applies to.
- `--input key=value` repeats and is read as the input's type. `--input-file` reads a YAML or JSON
  file of inputs; `--input` wins over it. At a terminal, `xp dispatch` asks for a required input
  you did not give.
- `--dry-run` prints what would run, where, what is left out and why, and starts nothing.
- `--follow` (`-f`) prints the log of each job and exits with how the run ended.

Follow the run with `xp runs show <run>` or `xp logs <run> -f`. A dispatch that cannot be planned,
such as one with an unknown flavor or a missing credential, is refused and nothing starts.

## Change a built-in workflow

Built-ins cannot be edited or deleted. Copy one and change the copy:

```sh
xp workflows copy acme/app dev-build dev-firebase
xp workflows show acme/app dev-firebase > dev-firebase.yaml   # then change the file
xp workflows edit acme/app dev-firebase -f dev-firebase.yaml
```

In the app, open Workflows, pick the built-in and press "Save as…". A copy remembers its built-in:
when the engine ships a newer version of it, the app says so and offers Compare.

Every save is a new version, and a run records the exact version it ran. These commands manage
your own workflows:

```sh
xp workflows create acme/app my-flow -f my-flow.yaml
xp workflows versions acme/app my-flow
xp workflows diff acme/app my-flow 1 2
xp workflows show acme/app my-flow --version 1
xp workflows rename acme/app my-flow qa-build
xp workflows archive acme/app qa-build        # --undo brings it back
xp workflows delete acme/app qa-build         # only if it never ran
```

## Start from a template

When you start a new workflow in the app, it offers templates beside the built-ins: Blank, Android
to Firebase, iOS to TestFlight, Tests only and Shorebird patch. Each is valid as it is; you name
and save the copy. The engine lists them at `GET /workflows/templates`.

## Write a workflow

A document has `schema: 1` and a list of `stages`. Stages run in order; the jobs of a stage run in
parallel. A stage starts when every job before it succeeded. `lock: project` lets only one run of
the workflow hold the project at a time.

This example runs the tests, builds an APK of each flavor and sends it to Firebase testers:

```yaml
# yaml-language-server: $schema=https://xpath.abdurahman.ly/schema/workflow-1.json
schema: 1
name: QA build
description: Runs the tests, then builds an APK of each flavor for Firebase testers.
inputs:
  notes:
    type: string
    description: Release notes for the testers.
    default: ""
  testerGroups:
    type: json
    description: Firebase tester group aliases.
    default: [qa]
  skipTests:
    type: boolean
    description: Leave the tests out.
    default: false
stages:
  - name: test
    jobs:
      test:
        name: Test ${{ app.name }}
        steps:
          - kind: git.checkout
          - kind: test
            if: "!inputs.skipTests"
          - kind: analyze
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }}
        matrix:
          platform: [android]
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: version.bump
          - kind: build.android
            with:
              artifact: apk
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }}
        matrix:
          platform: [android]
          flavor: ${{ flavors }}
        if: flavor.firebaseAppId.android
        steps:
          - kind: upload.firebase
            with:
              artifactsFrom: build
              appId: ${{ flavor.firebaseAppId.android }}
              groupAliases: ${{ inputs.testerGroups }}
              releaseNotes: ${{ inputs.notes }}
```

- **Steps.** `git.checkout` comes first in every job. `with` carries only what varies; the engine
  fills in the commit, the version, the flavor's ids and the secrets of its credentials. List the
  step types and their keys with `xp workflows schema` (`--kind build.ios` for one).
- **Runners.** Uploads, guards, gates, tags and pushes run only on the engine, so keep the build
  in a job without them and upload in a later stage with `artifactsFrom: <build job>`, as above.
- **Credentials** come by flavor: `upload.firebase` needs a `firebase_sa` credential,
  `upload.play` a `play_sa`, `upload.appStore` an `asc_key` or `apple_id`. See
  [Credentials](credentials.md).

## Inputs

An input is a value a dispatch can set, read as `inputs.<name>`. Each takes `type`,
`description`, `default`, `options` and `required`; an input with a default cannot be required.

| Type | Value |
|---|---|
| `string` | Text. |
| `boolean` | `true` or `false`. |
| `choice` | One of its `options`, which a choice must have. |
| `json` | Any value: a list, a map, a number. |
| `release` | An `x.y.z+build` of the project; the dispatch's `--release-version` fills it. |

An input without a type takes any value. A dispatch value replaces the whole default of that
input, and an input the workflow does not declare is refused.

## Expressions and conditions

`${{ ... }}` in `name`, matrix values and `with`, and every `if:`, use a small language that reads
values and runs nothing: literals, variables, `a.b`, `a['b']`, `a[0]`, `==`, `!=`, `!`, `&&`,
`||` and parentheses. Reading what is not there gives `null`; `null`, `false`, `0` and `''` are
false. A string that is exactly one `${{ }}` keeps the type of its value, so a list stays a list.

- `if:` on a job leaves out a matrix cell when it is false; on a step it leaves the step out.
- `if` is evaluated when you dispatch, not while the job runs.
- YAML reads a leading `!` as a tag, so quote it: `if: "!flavor.shorebird"`.
- Variables include `app`, `project`, `ref`, `sha`, `version`, `build`, `releaseVersion`,
  `platforms`, `flavors` and `inputs`; a matrix adds `platform` and `flavor`. The full list is in
  `xp workflows schema`.

## Matrix

A job with a `matrix` runs once per cell. The axes are only `platform` (`android`, `ios`) and
`flavor`. Write the values out, `platform: [android]`, or use `${{ platforms }}`,
`${{ flavors }}` or an input; the dispatch decides what those hold.

## Gates

`gate:` on a step puts an approval in front of it:

```yaml
- kind: git.push
  gate: push
```

The gates are `prod_release`, `prod_patch`, `store_submission`, `push`, `merge`, `rollout` and
`delete`. The job stops in `waiting_for_approval`, holding no slot or runner, until you decide.
Which gates a project enforces is a project setting. See [Approvals](approvals.md). Do not remove a
gate from a copy of a built-in to get past an approval.

## Validate a workflow

The engine checks a document on every save and never saves one with issues. Check it first:

```sh
xp workflows validate my-flow.yaml
```

It exits with 0 when the document is valid, and with 65 and one `line:column: message` per issue
otherwise: an unknown key or step type, a `with` key the step does not take, an expression that
does not parse, an input that is not declared. A typo comes back with the name it most likely
meant. Some problems only show at dispatch, such as a missing credential: dispatch once with
`--dry-run` or the smallest matrix.

For completion in your editor, the JSON schema is published at
`https://xpath.abdurahman.ly/schema/workflow-1.json`; start the file with the
`yaml-language-server` line of the example above. The engine's check is the one that counts.

More: [Workflows and the scheduler](../reference/workflows.md).
