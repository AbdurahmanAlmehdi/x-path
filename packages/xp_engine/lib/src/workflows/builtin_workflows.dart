/// The workflows the engine makes for every project (`builtin = true`).
///
/// Each is a workflow document like any other, composed of the registered
/// steps; the owner copies one to change it. When a later version of the
/// engine ships a different document, the project gets it as a new version.
const builtinWorkflows = <String, String>{
  'dev-build': _devBuild,
  'prod-release': _prodRelease,
  'release-merge': _releaseMerge,
  'release-rollout': _releaseRollout,
  'shorebird-patch': _shorebirdPatch,
  'shorebird-track': _shorebirdTrack,
  'smoke-build': _smokeBuild,
  'test': _test,
};

// A dev build is the build of ship.sh `release dev`: flutter build, then
// Firebase App Distribution for Android and TestFlight for iOS. Unlimited:
// no lock, only the slots of the runners limit how many run.
//
// Three stages keep what only the engine does apart from the build (ADR 0010):
// `check` and `upload` run on the engine, `build` has no engine-only step and
// can be leased to a runner. The runner uploads what it builds to the
// engine's artifact store, and `upload` takes it from there. The version
// commit of a dev build is never pushed, so the build job bumps the version
// itself, in its own worktree.
const _devBuild = r'''
schema: 1
name: Dev build
description: >-
  Builds the dev flavors and sends them to testers: Android to Firebase App
  Distribution, iOS to TestFlight.
inputs:
  firebaseAppIds:
    type: json
    description: >-
      Firebase app ids by flavor and platform, for example
      {dev: {android: "1:123456789012:android:abcdef"}}. A flavor without one
      uses the id of its profile; a build with neither is not uploaded.
  testerGroups:
    type: json
    description: Firebase tester group aliases.
    default: []
  notes:
    type: string
    description: Release notes for the testers.
    default: ""
  appleAppIds:
    type: json
    description: >-
      App Store Connect app ids by flavor, for example {dev: "1234567890"}. A
      flavor without one uses the id of its profile; an iOS build with neither
      is not uploaded.
  exportOptionsPlist:
    type: string
    description: The export options of iOS builds, relative to the app.
    default: ios/ExportOptions.plist
  dartDefineFile:
    type: string
    description: The --dart-define-from-file file, relative to the app.
stages:
  - name: check
    jobs:
      check:
        name: Check ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
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
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: version.bump
          - kind: build.android
            if: platform == 'android'
            with:
              artifact: apk
              dartDefineFile: ${{ inputs.dartDefineFile }}
          - kind: build.ios
            if: platform == 'ios'
            with:
              exportOptionsPlist: ${{ inputs.exportOptionsPlist }}
              dartDefineFile: ${{ inputs.dartDefineFile }}
          - kind: record.manifest
            with:
              dartDefineFile: ${{ inputs.dartDefineFile }}
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        if: >-
          (platform == 'android' && (inputs.firebaseAppIds[flavor.name].android || flavor.firebaseAppId.android))
          || (platform == 'ios' && (inputs.appleAppIds[flavor.name] || flavor.appleAppId))
        steps:
          - kind: upload.firebase
            if: platform == 'android' && (inputs.firebaseAppIds[flavor.name].android || flavor.firebaseAppId.android)
            with:
              artifactsFrom: build
              appId: ${{ inputs.firebaseAppIds[flavor.name].android || flavor.firebaseAppId.android }}
              groupAliases: ${{ inputs.testerGroups }}
              releaseNotes: ${{ inputs.notes }}
          - kind: upload.appStore
            if: platform == 'ios' && (inputs.appleAppIds[flavor.name] || flavor.appleAppId)
            with:
              artifactsFrom: build
              appleAppId: ${{ inputs.appleAppIds[flavor.name] || flavor.appleAppId }}
''';

// A production release is ship.sh `release prod` plus the release model: the
// version commit and the release branch are made once (prepare), every
// platform builds that very commit (build), and the tag and the release pull
// request come last (finalize). Everything that can be checked is checked
// first; then the owner approves the release before the branch is cut and
// anything is built or uploaded, and the push before it leaves the machine
// (D-13). The run is a release (D-17) that the stores then review; a new build
// of the same version after a rejection dispatches this workflow again with
// `release` set, which skips the check that the version was not released
// before.
//
// Five stages keep what only the engine does apart from the build (ADR 0010):
// `prepare`, `check`, `upload` and `finalize` run on the engine, `build` has
// no engine-only step and can be leased to a runner. A runner fetches the
// version commit from GitHub with its own SSH key (ADR 0009), so `prepare`
// pushes the release branch right after it cuts it (the owner approves the
// push there; the approval covers the tag push of `finalize` too, as it is
// the same project, commit, version and run). The runner uploads what it
// builds to the engine's artifact store, and `upload` takes it from there.
const _prodRelease = r'''
schema: 1
name: Production release
description: >-
  Releases a production flavor: writes the version, builds and uploads to the
  stores, then tags the release and pushes it. One at a time per project, and
  only with the owner's approval.
lock: project
inputs:
  firebaseAppIds:
    type: json
    description: >-
      Firebase app ids by flavor and platform; a flavor without one uses the
      id of its profile. A Shorebird flavor with one is also uploaded to
      Firebase App Distribution as an APK.
  testerGroups:
    type: json
    description: Firebase tester group aliases.
    default: []
  notes:
    type: string
    description: Release notes.
    default: ""
  appleAppIds:
    type: json
    description: >-
      App Store Connect app ids by flavor; a flavor without one uses the id of
      its profile. An iOS build with neither is not uploaded.
  playTrack:
    type: string
    description: The Google Play track an Android build goes to.
    default: internal
  exportOptionsPlist:
    type: string
    description: The export options of iOS builds, relative to the app.
    default: ios/ExportOptions.plist
  dartDefineFile:
    type: string
    description: The --dart-define-from-file file, relative to the app.
stages:
  - name: prepare
    jobs:
      prepare:
        name: Prepare ${{ flavor.name }}
        matrix:
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials]
          - kind: version.bump
          - kind: guard
            with:
              checks: [versionSync]
          - kind: guard
            if: "!release"
            with:
              checks: [newReleaseNumber]
          - kind: git.releaseBranch
            gate: prod_release
          - kind: git.push
            gate: push
            with:
              tag: false
  - name: check
    jobs:
      check:
        name: Check ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
            with:
              commitFrom: prepare
          - kind: guard
            with:
              checks: [versionSync, buildNumberReuse, credentials]
          - kind: guard
            if: platform == 'android'
            with:
              checks: [playTargetSdk]
          - kind: guard
            if: platform == 'ios'
            with:
              checks: [appStoreTrain]
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
            with:
              commitFrom: prepare
          - kind: shorebird.release
            if: flavor.shorebird
            with:
              artifact: apk
              exportOptionsPlist: ${{ inputs.exportOptionsPlist }}
              dartDefineFile: ${{ inputs.dartDefineFile }}
              obfuscate: true
          - kind: build.android
            if: platform == 'android' && !flavor.shorebird
            with:
              artifact: aab
              dartDefineFile: ${{ inputs.dartDefineFile }}
              obfuscate: true
          - kind: build.ios
            if: platform == 'ios' && !flavor.shorebird
            with:
              exportOptionsPlist: ${{ inputs.exportOptionsPlist }}
              dartDefineFile: ${{ inputs.dartDefineFile }}
              obfuscate: true
          - kind: symbols.archive
            with:
              dartDefineFile: ${{ inputs.dartDefineFile }}
              obfuscate: true
          - kind: record.manifest
            with:
              dartDefineFile: ${{ inputs.dartDefineFile }}
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        if: >-
          (platform == 'android' && (flavor.credentials.play_sa
          || (flavor.shorebird && (inputs.firebaseAppIds[flavor.name].android || flavor.firebaseAppId.android))))
          || (platform == 'ios' && (inputs.appleAppIds[flavor.name] || flavor.appleAppId))
        steps:
          - kind: upload.play
            if: platform == 'android' && flavor.credentials.play_sa
            with:
              artifactsFrom: build
              track: ${{ inputs.playTrack }}
              releaseNotes:
                en-US: ${{ inputs.notes }}
          - kind: upload.firebase
            if: platform == 'android' && flavor.shorebird && (inputs.firebaseAppIds[flavor.name].android || flavor.firebaseAppId.android)
            with:
              artifactsFrom: build
              appId: ${{ inputs.firebaseAppIds[flavor.name].android || flavor.firebaseAppId.android }}
              groupAliases: ${{ inputs.testerGroups }}
              releaseNotes: ${{ inputs.notes }}
          - kind: upload.appStore
            if: platform == 'ios' && (inputs.appleAppIds[flavor.name] || flavor.appleAppId)
            with:
              artifactsFrom: build
              appleAppId: ${{ inputs.appleAppIds[flavor.name] || flavor.appleAppId }}
  - name: finalize
    jobs:
      tag:
        name: Tag ${{ flavor.name }}
        matrix:
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
            with:
              commitFrom: prepare
          - kind: git.tag
          - kind: git.push
            gate: push
            with:
              branch: false
          - kind: github.createPr
''';

// The merge of the pull request of a release (D-17): started by
// POST /releases/{id}/merge once every store is live. The merge is a gated
// action, so the run waits for the owner to approve it (D-13), and the pull
// request is merged with a merge commit (ADR 0007).
const _releaseMerge = '''
schema: 1
name: Merge the release pull request
description: >-
  Merges the pull request of a release once every store it went to is live.
  Started with POST /releases/{id}/merge; the merge waits for the owner's
  approval.
stages:
  - name: merge
    jobs:
      merge:
        name: Merge the release pull request
        steps:
          - kind: github.mergePr
            gate: merge
''';

// The rollout of a release once it is in a store (U7a): Apple's phased
// release and Google Play's staged rollout. The change is a gated action
// (D-13), and only the engine reaches the stores.
const _releaseRollout = r'''
schema: 1
name: Change the rollout of a release
description: >-
  Pauses, resumes or completes Apple's phased release, or sets, halts or
  completes Google Play's staged rollout. Started from the release; the change
  waits for the owner's approval.
inputs:
  store:
    type: choice
    options: [apple, play]
  action:
    type: choice
    options: [pause, resume, complete, halt, fraction]
  userFraction:
    type: json
    description: For "fraction", the share of users, above 0, at most 1.
stages:
  - name: rollout
    jobs:
      rollout:
        name: ${{ inputs.store }} rollout, ${{ inputs.action }} ${{ inputs.userFraction }}
        steps:
          - kind: store.rollout
            gate: rollout
            with:
              store: ${{ inputs.store }}
              action: ${{ inputs.action }}
              userFraction: ${{ inputs.userFraction }}
''';

// A patch is ship.sh `patch prod`: an over-the-air code patch against an
// exact release, with the Flutter version of that release. It changes no
// version, so every job builds the dispatched commit.
//
// The checks and the owner's approval run on the engine (`check`), the patch
// itself, which needs no engine-only step, can be leased to a runner (`patch`,
// ADR 0010; the Shorebird key goes to the runner for the one job, ADR 0012),
// and the tag comes last (`finalize`). The approval is asked in front of the
// last check, so that the owner is asked only about a patch that passed the
// others.
// U7b: a patch the owner tried on a staging track goes to every user, or a
// patch that went wrong is rolled back, from the release page. Either way
// every user of the release gets the change, so it waits for the same
// approval as a production patch.
const _shorebirdTrack = r'''
schema: 1
name: Move a Shorebird patch
description: >-
  Promotes a Shorebird patch of a release to the stable track, or rolls it
  back. Started from the release; the change waits for the owner's approval.
inputs:
  patchNumber:
    type: json
    description: The patch of the release, a number from 1.
  action:
    type: choice
    options: [promote, rollback]
stages:
  - name: track
    jobs:
      track:
        name: ${{ inputs.action }} patch ${{ inputs.patchNumber }} of ${{ flavor.name }}
        matrix:
          flavor: ${{ flavors }}
        if: flavor.shorebird
        steps:
          - kind: shorebird.track
            gate: prod_patch
            with:
              patchNumber: ${{ inputs.patchNumber }}
              action: ${{ inputs.action }}
''';

const _shorebirdPatch = r'''
schema: 1
name: Shorebird patch
description: >-
  Publishes an over-the-air code patch to a production release. Dispatch it
  with the release it patches (releaseVersion, for example 5.4.1+3283). One at
  a time per project, and only with the owner's approval.
lock: project
inputs:
  releaseVersion:
    type: release
    description: >-
      The release the patch applies to, for example 5.4.1+3283. The dispatch's
      releaseVersion when it gives none.
  exportOptionsPlist:
    type: string
    description: The export options of iOS builds, relative to the app.
    default: ios/ExportOptions.plist
  dartDefineFile:
    type: string
    description: The --dart-define-from-file file, relative to the app.
  allowNativeDiffs:
    type: boolean
    description: >-
      Publish the patch although Shorebird reports native changes. Only for
      differences you have checked are not real native changes.
    default: false
stages:
  - name: check
    jobs:
      check:
        name: Check the patch of ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        if: flavor.shorebird
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [credentials, patchTarget, patchNativeDiff]
          - kind: guard
            gate: prod_patch
            with:
              checks: [source]
  - name: patch
    jobs:
      patch:
        name: Patch ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        if: flavor.shorebird
        steps:
          - kind: git.checkout
          - kind: shorebird.patch
            with:
              exportOptionsPlist: ${{ inputs.exportOptionsPlist }}
              dartDefineFile: ${{ inputs.dartDefineFile }}
              allowNativeDiffs: ${{ inputs.allowNativeDiffs }}
  - name: finalize
    jobs:
      tag:
        name: Tag the patch of ${{ flavor.name }}
        matrix:
          flavor: ${{ flavors }}
        if: flavor.shorebird
        steps:
          - kind: git.checkout
          - kind: git.tag
          - kind: git.push
            gate: push
''';

// A smoke build is the first green build of a new project: an APK of each
// flavor, signed with the debug key instead of the flavor's keystore, so it
// needs no credential, no store id and no version bump. It uploads nothing
// and runs on any runner with Android (U5a).
const _smokeBuild = r'''
schema: 1
name: Smoke build
description: >-
  Builds an Android APK of each flavor without its keystore, to see a green
  build before signing and the stores are set up. Nothing is uploaded.
stages:
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }}
        matrix:
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: build.android
            with:
              artifact: apk
              keystore: false
''';

// The tests: flutter test --machine against the baseline, then the analyzer.
const _test = r'''
schema: 1
name: Test
description: Runs the tests of the app against the baseline, then the analyzer.
inputs:
  paths:
    type: json
    description: Test files or folders, relative to the app. All by default.
    default: []
  tags:
    type: json
    description: Run only the tests with all of these tags.
    default: []
stages:
  - name: test
    jobs:
      test:
        name: Test ${{ app.name }}
        steps:
          - kind: git.checkout
          - kind: test
            with:
              paths: ${{ inputs.paths }}
              tags: ${{ inputs.tags }}
          - kind: analyze
''';
