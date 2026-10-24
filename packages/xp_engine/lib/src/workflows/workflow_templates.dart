import 'package:xp_engine/src/workflows/builtin_workflows.dart';

/// A document a new workflow can start from: what the app's "New workflow"
/// offers beside the built-ins.
///
/// Like the built-ins, a template keeps what only the engine does (`check`,
/// `upload`) apart from the build, so a runner can take the build.
typedef WorkflowTemplateDocument = ({
  String title,
  String description,
  String yaml,
});

/// The templates of new workflows, by id, in the order they are offered.
/// Each is a valid document; the owner names and saves the copy.
final workflowTemplates = <String, WorkflowTemplateDocument>{
  'blank': (
    title: 'Blank',
    description: 'One stage with one job that checks out the commit.',
    yaml: _blank,
  ),
  'android-firebase': (
    title: 'Android to Firebase',
    description:
        'Builds an APK of each flavor and sends it to Firebase App '
        'Distribution testers.',
    yaml: _androidFirebase,
  ),
  'ios-testflight': (
    title: 'iOS to TestFlight',
    description:
        'Builds an IPA of each flavor and uploads it to App Store Connect '
        'for TestFlight.',
    yaml: _iosTestFlight,
  ),
  'tests': (
    title: 'Tests only',
    description: 'Runs the tests of the app, then the analyzer.',
    yaml: builtinWorkflows['test']!,
  ),
  'shorebird-patch': (
    title: 'Shorebird patch',
    description:
        'Publishes an over-the-air patch to a production release, with the '
        "owner's approval.",
    yaml: builtinWorkflows['shorebird-patch']!,
  ),
};

const _blank = '''
schema: 1
name: New workflow
stages:
  - name: build
    jobs:
      build:
        steps:
          - kind: git.checkout
''';

const _androidFirebase = r'''
schema: 1
name: Android to Firebase
description: >-
  Builds an APK of each flavor and sends it to Firebase App Distribution
  testers.
inputs:
  testerGroups:
    type: json
    description: Firebase tester group aliases.
    default: []
  notes:
    type: string
    description: Release notes for the testers.
    default: ""
stages:
  - name: check
    jobs:
      check:
        name: Check ${{ flavor.name }}
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
''';

const _iosTestFlight = r'''
schema: 1
name: iOS to TestFlight
description: >-
  Builds an IPA of each flavor and uploads it to App Store Connect for
  TestFlight.
inputs:
  exportOptionsPlist:
    type: string
    description: The export options of the build, relative to the app.
    default: ios/ExportOptions.plist
stages:
  - name: check
    jobs:
      check:
        name: Check ${{ flavor.name }}
        matrix:
          platform: [ios]
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials, appStoreTrain]
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }}
        matrix:
          platform: [ios]
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: version.bump
          - kind: build.ios
            with:
              exportOptionsPlist: ${{ inputs.exportOptionsPlist }}
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }}
        matrix:
          platform: [ios]
          flavor: ${{ flavors }}
        if: flavor.appleAppId
        steps:
          - kind: upload.appStore
            with:
              artifactsFrom: build
              appleAppId: ${{ flavor.appleAppId }}
''';
