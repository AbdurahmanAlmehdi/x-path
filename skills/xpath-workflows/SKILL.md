---
name: xpath-workflows
description: Write, change and validate XPath workflow YAML (schema 1), the documents XPath dispatches to build, test, upload and release Flutter apps. Use when creating a workflow, copying and changing a built-in one (dev-build, prod-release, release-merge, release-rollout, shorebird-patch, shorebird-track, smoke-build, test), adding inputs with defaults (such as firebaseAppIds or appleAppIds), stages, jobs, matrix, if expressions, gates or capabilities, choosing step kinds and their `with` keys, or fixing a workflow_invalid error.
license: Apache-2.0
---

# XPath workflows

A workflow is a YAML document. Dispatching it makes a run; its jobs wait in the engine's
database until the scheduler starts them, on the engine or on a remote runner. The engine checks
every document against schema 1 and its own step catalogue, and never saves one with issues.

## The document

```yaml
schema: 1                      # required, always 1
name: Dev build                # optional
description: ...               # optional
lock: project                  # optional: one run of this workflow at a time per project
inputs:                        # optional: variables a dispatch can set
  notes: {type: string, description: Release notes, default: ""}
  appId: {description: The app id, required: true}
  track: {type: choice, options: [internal, beta], default: internal}
  extra:                       # empty: no default, not required
stages:                        # required; run in order
  - name: build
    jobs:                      # run in parallel, as slots allow
      build:                   # the job id, unique in the whole workflow
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:                # one job per cell
          platform: ${{ platforms }}     # or [android, ios]
          flavor: ${{ flavors }}
        if: platform == 'android'        # a cell without a job when false
        capabilities: [flutter]          # on top of what the steps need
        steps:
          - kind: build.android          # a step type
            with: {artifact: apk}        # what the step type takes
            if: "!flavor.shorebird"      # the step is left out when false
            gate: prod_release           # the owner approves first
```

Allowed keys, and nothing else (an unknown key is an issue that lists the allowed ones):

| Where | Keys |
|---|---|
| the workflow | `schema`, `name`, `description`, `lock`, `inputs`, `stages` |
| an input | `type`, `description`, `options`, `default`, `required` (an input with a default cannot be required) |
| a stage | `name`, `jobs` |
| a job | `name`, `matrix`, `if`, `capabilities`, `steps` |
| a step | `kind`, `with`, `if`, `gate` |

- Input types (optional): `string` (text), `boolean` (`true`/`false`), `choice` (one of its
  `options`, which only a choice has and a choice must have), `json` (any value: a list, a map, a
  number) and `release` (`x.y.z+build` of the project; a dispatch's `releaseVersion` fills it,
  and it fills `releaseVersion`). A default must be of the input's type. An input without a type
  takes any value; the CLI sends it as JSON when it parses, else as text, and the app as text.
- Input names: letters, digits and `_`, not starting with a digit. Job ids: a letter, then
  letters, digits, `-` and `_`.
- `lock` can only be `project`. A locked run holds the project from its first job until it
  succeeds, fails or is cancelled, through any gate it waits at.
- A stage starts when every job of the stages before it succeeded.

## Matrix

Axes are only `platform` and `flavor`. `platform` takes `android` and `ios`. Write the values out
(`[android]`) or use one placeholder: `${{ platforms }}`, `${{ flavors }}` or an input. A job is
made for each cell whose `if` is true. The default platforms are what the app has; the default
flavors are the production flavors for a workflow with `lock: project` and the others otherwise
(an app with one flavor always uses it).

## Expressions

`if:` and `${{ ... }}` in `name`, matrix values and `with` are a small language that reads values
and runs nothing:

- literals (`'x'`, `"x"`, numbers, `true`, `false`, `null`), variables, `a.b`, `a['b']`, `a[0]`;
- `==`, `!=`, `!`, `&&`, `||` and parentheses. There is no function, assignment or loop.
- Reading what is not there gives `null`, also past a `null`. `null`, `false`, `0` and `''` are
  false. `&&` and `||` return one of their operands, so `a && b || c` picks a value.
- A string that is exactly one `${{ }}` keeps the type of its value (a list stays a list); with
  text around it, it becomes text.
- YAML reads a leading `!` as a tag: quote it, `if: "!flavor.shorebird"`.
- `if` is evaluated when the workflow is dispatched, not while the job runs.

Variables from the dispatch: `app` (`name`, `path`, `hasIos`, `hasAndroid`, `version`),
`project` (`id`, `fullName`, `baseBranch`), `ref`, `sha`, `version` (`x.y.z`), `build`, `bump`,
`releaseVersion`, `patch`, `release`, `platforms`, `flavors` and `inputs` (the document's
defaults, then what the dispatch gave). A matrix adds `platform` and `flavor` (`name`, `prod`,
`shorebird`, `implicit`, `entrypoint`, `iosBundleId`, `androidAppId`, `shorebirdAppId`,
`firebaseAppId` (by platform, `flavor.firebaseAppId.android`), `appleAppId`, and
`credentials.<kind>` for each credential the flavor has, such as `flavor.credentials.play_sa`).

## Steps

`with` carries only what varies. The engine fills in the worktree, the commit, the version and
build number, the flavor and its ids, the Flutter pin and the secrets of the flavor's
credentials. Every step kind and its `with` keys are in
[references/step-kinds.md](references/step-kinds.md). The live list for the engine you talk to:

```sh
xp workflows schema                     # the step types by group, the gates, the variables
xp workflows schema --kind build.ios    # one step type: what it does, what runs it, its keys
```

With MCP, call `get_workflow_schema` (`kind` optional) or read the resource
`xpath://workflows/schema`. Each step type comes with a title, a description, its group, the
runner capabilities it needs (any one set), and its `with` keys typed (`string`, `boolean`,
`number`, `list`, `map`) with `required`, `default`, `options` and a description. The gates come
with labels, and `variables` lists every path an expression can read.

For completion in an editor, start the file with:

```yaml
# yaml-language-server: $schema=https://xpath.abdurahman.ly/schema/workflow-1.json
```

Rules that shape every workflow:

- **`git.checkout` comes first in every job.** `with: {commitFrom: <job id>}` starts from the
  version commit an earlier job of the run made, so every platform builds the tagged commit.
- **`version.bump` makes the run allocate a build number** at dispatch (never handed back).
  `record.manifest`, `git.tag` and `git.push` need one.
- **Engine-only steps**: `upload.*`, `github.*`, `git.push`, `git.tag`, `git.releaseBranch`,
  `gate`, `guard` and `test`. A job is leased whole, so a job with one of them never goes to a
  remote runner. Keep builds in jobs without them, as the built-ins do (ADR 0010), and upload in
  a later stage with `artifactsFrom: <build job id>`.
- **Credentials come by flavor and kind.** `upload.firebase` needs a `firebase_sa` credential,
  `upload.play` a `play_sa`, `upload.appStore` an `asc_key` or `apple_id`. A dispatch that
  plans such a step without the credential is refused with `workflow_invalid`.

## Gates and capabilities

`gate: prod_release | prod_patch | store_submission | push | merge | rollout | delete` on a step puts an
approval in front of it. The job stops in `waiting_for_approval` (holding no slot or runner)
until the owner decides with an `app` or `cli` token. Which gates a project enforces is the
owner's setting (`xp gates show <project>`; only the app turns a gate off). Never remove a gate
from a copy of a built-in to get past an approval; ask the owner.

Capabilities are `ios-sign`, `android`, `flutter` and `swift-linux`, plus `ios-linux`, which a
workflow cannot name. A job needs what it declares plus what its steps imply: `android` and
`flutter` for `build.android`; `flutter` and any of `ios-sign` (a Mac) or `ios-linux` (a Linux
runner with omarchy-apple-dev, ADR 0014) for `build.ios`; `ios-sign` for `upload.appStore` with an
Apple ID only; the platform's for Shorebird steps; `flutter` for `test` and `analyze`. The planner
sends an iOS build to a Mac (narrows it to `ios-sign`, with the reasons in the dry run and the queue
message) when Linux cannot build it: Linux iOS turned off for the app (`xp projects set <p>
--no-ios-linux`), Shorebird iOS, a debug or profile build, an app extension, the iOS Simulator,
`ios.stripAndReexport`, a flavor without an Apple Distribution identity and an ASC key, or what the
scan found (CocoaPods plugins, a Run Script phase beyond Flutter's own, Flutter older than 3.47, and
per flavor a multi-size icon set, an Info.plist other than `Runner/Info.plist` or an icon set outside
`Runner/Assets.xcassets`). Flavors and entry points build on Linux. A Linux workflow has no iOS Simulator:
device tests and screenshots run on an Android emulator; a `command` step calling `xcrun simctl`
needs a Mac.

## Built-ins: copy, never edit

Every project has `dev-build`, `prod-release`, `release-merge`, `release-rollout`,
`shorebird-patch`, `shorebird-track`, `smoke-build` and `test`.
They cannot be edited or deleted (`409`). Their stages and steps are in
[references/built-in-workflows.md](references/built-in-workflows.md). To change one, copy its YAML
into a workflow of your own:

```sh
xp workflows show acme/app dev-build > dev-firebase.yaml   # prints the YAML only
xp --json workflows show acme/app dev-build                # id, versions and "yaml" as JSON
```

In the app: Workflows, pick the built-in, Save as. Or `xp workflows copy acme/app dev-build
dev-firebase`. A copy of a built-in remembers it: when the engine ships a newer version of the
built-in, the app offers to compare (what the built-in changed, and what the copy changed).

Every save is a new version; a job records the exact version it ran (`xp workflows show <p> <w>
--version n`). `xp workflows versions <p> <w>` lists them and `xp workflows diff <p> <w> <from>
[<to>]` shows what changed. `xp workflows rename <p> <w> <name>` renames; `xp workflows archive
<p> <w>` keeps a workflow with its runs and stops it being dispatched (`--undo` brings it back);
`xp workflows delete <p> <w>` deletes one only if it never ran.

## Validate and save

```sh
xp workflows validate workflow.yaml                   # exit 65 and line:column: message hint on issues
xp workflows create acme/app dev-firebase -f workflow.yaml
xp workflows edit acme/app dev-firebase -f workflow.yaml   # a new version
```

A document is valid or not for every project alike, so validating needs no project. MCP:
`validate_workflow` (`project` optional), `create_workflow`, `update_workflow` (each validates
first and saves nothing with issues). API: `POST /workflows/validate` with `{"yaml": "..."}`
always answers `200` with `valid` and `issues` (`line`, `column`, `message`, and a `hint` such
as `Did you mean "inputs.firebaseAppIds"?`). A `422 workflow_invalid` on create or save carries
the same `issues` in its error.

Validation catches: unknown keys, wrong types, unknown step types or `with` keys, a `with` key
a step type needs (`exportOptionsPlist` of `build.ios`, `appId` of `upload.firebase`, ...), a
`with` value of the wrong shape or not one of its options, unknown capabilities or gates, a
matrix axis other than `platform` or `flavor`, a platform other than `android` or `ios`, a job
id used twice, `commitFrom` or `artifactsFrom` naming a job not in an earlier stage, an
expression that does not parse, a variable that does not exist there, an input the workflow does
not declare (`inputs.x`), and a field `flavor`, `app` or `project` does not have. A typo comes
back with the name it most likely meant.
Some problems only show at dispatch (`422 workflow_invalid`): an unknown flavor, a missing
credential, a value a step refuses. Validate, then dispatch once with the smallest matrix.

## Worked example: dev build to Firebase with app ids as defaults

The built-in `dev-build` uploads Android when `firebaseAppIds` is given at dispatch or the flavor
has a Firebase app id in its profile (`flavor.firebaseAppId`). This copy carries the ids as input
defaults, builds Android only and sends the APK to a tester group.

```yaml
schema: 1
name: Dev build to Firebase
description: Builds the dev flavors for Android and sends them to Firebase App Distribution.
inputs:
  firebaseAppIds:
    description: Firebase app ids by flavor and platform.
    default:
      dev:
        android: "1:123456789012:android:abcdef"
  testerGroups:
    description: Firebase tester group aliases.
    default: [qa]
  notes:
    description: Release notes for the testers.
    default: ""
  dartDefineFile:
    description: The --dart-define-from-file file, relative to the app.
stages:
  - name: check
    jobs:
      check:
        name: Check ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: [android]
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials]
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: [android]
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: version.bump
          - kind: build.android
            with:
              artifact: apk
              dartDefineFile: ${{ inputs.dartDefineFile }}
          - kind: record.manifest
            with:
              dartDefineFile: ${{ inputs.dartDefineFile }}
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: [android]
          flavor: ${{ flavors }}
        if: inputs.firebaseAppIds[flavor.name].android
        steps:
          - kind: upload.firebase
            with:
              artifactsFrom: build
              appId: ${{ inputs.firebaseAppIds[flavor.name].android }}
              groupAliases: ${{ inputs.testerGroups }}
              releaseNotes: ${{ inputs.notes }}
```

Why it is shaped this way:

- `check` and `upload` run on the engine (`guard` and `upload.firebase` are engine-only);
  `build` has no engine-only step, so it can run on a runner, which uploads the APK to the
  engine's artifact store. `artifactsFrom: build` takes the APK of the build job of the same
  matrix cell.
- The `upload` job's `if` drops cells whose flavor has no app id, so a flavor without one is
  built and kept but not uploaded.
- The flavor needs a `firebase_sa` credential (skill `xpath-setup`), or the dispatch is refused.
- A dev build pushes nothing: `version.bump` commits in the job's own worktree only.

Save and run it:

```sh
xp workflows validate dev-firebase.yaml
xp workflows create acme/app dev-firebase -f dev-firebase.yaml
xp dispatch acme/app dev-firebase --flavor dev --follow   # prints the logs, exits 0 on success
xp dispatch acme/app dev-firebase --flavor dev --input 'notes=Try the new checkout'
```

A dispatch input replaces the whole default of that input, so
`--input 'firebaseAppIds={"staging": {"android": "1:..."}}'` drops the `dev` id for that run. An
input the workflow does not declare is refused, and a `required` input must be given.

## More

- Dispatching, following runs and approvals: skill `xpath-release`.
- In the XPath repository: `docs/guide/workflows.md`, `docs/reference/workflows.md` and
  `docs/reference/runners.md`.
