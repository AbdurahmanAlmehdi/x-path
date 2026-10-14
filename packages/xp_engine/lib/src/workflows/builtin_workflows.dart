/// The workflows the engine makes for every project (`builtin = true`).
///
/// Each is a workflow document like any other, composed of the registered
/// steps; the owner copies one to change it. When a later version of the
/// engine ships a different document, the project gets it as a new version.
const builtinWorkflows = <String, String>{
  'dev-build': _devBuild,
  'prod-release': _prodRelease,
  'shorebird-patch': _shorebirdPatch,
  'test': _test,
};

// A dev build is the build of ship.sh `release dev`: flutter build, then
// Firebase App Distribution for Android and TestFlight for iOS. Unlimited:
// no lock, only the slots of the runners limit how many run.
const _devBuild = r'''
schema: 1
name: Dev build
description: >-
  Builds the dev flavors and sends them to testers: Android to Firebase App
  Distribution, iOS to TestFlight.
inputs:
  firebaseAppIds:
    description: >-
      Firebase app ids by flavor and platform, for example
      {dev: {android: "1:123456789012:android:abcdef"}}. A build without one
      is not uploaded.
  testerGroups:
    description: Firebase tester group aliases.
    default: []
  notes:
    description: Release notes for the testers.
    default: ""
  appleAppIds:
    description: >-
      App Store Connect app ids by flavor, for example {dev: "1234567890"}. An
      iOS build without one is not uploaded.
  exportOptionsPlist:
    description: The export options of iOS builds, relative to the app.
    default: ios/ExportOptions.plist
  dartDefineFile:
    description: The --dart-define-from-file file, relative to the app.
stages:
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials]
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
          - kind: upload.firebase
            if: platform == 'android' && inputs.firebaseAppIds[flavor.name].android
            with:
              appId: ${{ inputs.firebaseAppIds[flavor.name].android }}
              groupAliases: ${{ inputs.testerGroups }}
              releaseNotes: ${{ inputs.notes }}
          - kind: upload.appStore
            if: platform == 'ios' && inputs.appleAppIds[flavor.name]
            with:
              appleAppId: ${{ inputs.appleAppIds[flavor.name] }}
''';

// A production release is ship.sh `release prod` plus the release model: the
// version commit and the release branch are made once (prepare), every
// platform builds that very commit (build), and the tag and the push come
// last (finalize). Everything that can be checked is checked first; then the
// owner approves the release before the branch is cut and anything is built or
// uploaded, and the push before it leaves the machine (D-13).
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
    description: >-
      Firebase app ids by flavor and platform. A Shorebird flavor with one is
      also uploaded to Firebase App Distribution as an APK.
  testerGroups:
    description: Firebase tester group aliases.
    default: []
  notes:
    description: Release notes.
    default: ""
  appleAppIds:
    description: >-
      App Store Connect app ids by flavor. An iOS build without one is not
      uploaded.
  playTrack:
    description: The Google Play track an Android build goes to.
    default: internal
  exportOptionsPlist:
    description: The export options of iOS builds, relative to the app.
    default: ios/ExportOptions.plist
  dartDefineFile:
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
              checks: [versionSync, newReleaseNumber]
          - kind: git.releaseBranch
            gate: prod_release
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
          - kind: upload.play
            if: platform == 'android' && flavor.credentials.play_sa
            with:
              track: ${{ inputs.playTrack }}
              releaseNotes:
                en-US: ${{ inputs.notes }}
          - kind: upload.firebase
            if: platform == 'android' && flavor.shorebird && inputs.firebaseAppIds[flavor.name].android
            with:
              appId: ${{ inputs.firebaseAppIds[flavor.name].android }}
              groupAliases: ${{ inputs.testerGroups }}
              releaseNotes: ${{ inputs.notes }}
          - kind: upload.appStore
            if: platform == 'ios' && inputs.appleAppIds[flavor.name]
            with:
              appleAppId: ${{ inputs.appleAppIds[flavor.name] }}
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
''';

// A patch is ship.sh `patch prod`: an over-the-air code patch against an
// exact release, with the Flutter version of that release. It changes no
// version, so every job builds the dispatched commit.
const _shorebirdPatch = r'''
schema: 1
name: Shorebird patch
description: >-
  Publishes an over-the-air code patch to a production release. Dispatch it
  with the release it patches (releaseVersion, for example 5.4.1+3283). One at
  a time per project, and only with the owner's approval.
lock: project
inputs:
  exportOptionsPlist:
    description: The export options of iOS builds, relative to the app.
    default: ios/ExportOptions.plist
  dartDefineFile:
    description: The --dart-define-from-file file, relative to the app.
  allowNativeDiffs:
    description: >-
      Publish the patch although Shorebird reports native changes. Only for
      differences you have checked are not real native changes.
    default: false
stages:
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
          - kind: guard
            with:
              checks: [source, patchTarget, patchNativeDiff, credentials]
          - kind: shorebird.patch
            gate: prod_patch
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

// The tests: flutter test --machine against the baseline, then the analyzer.
const _test = r'''
schema: 1
name: Test
description: Runs the tests of the app against the baseline, then the analyzer.
inputs:
  paths:
    description: Test files or folders, relative to the app. All by default.
    default: []
  tags:
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
