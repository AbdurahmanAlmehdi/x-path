import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/helpers.dart';

const releaseYaml = r'''
name: Production release
lock: project
inputs:
  appleAppIds:
    description: By flavor.
stages:
  - name: prepare
    jobs:
      prepare:
        name: Prepare ${{ flavor.name }}
        matrix:
          flavor: ${{ flavors }}
        steps:
          - kind: guard
          - kind: git.releaseBranch
            gate: prod_release
          - kind: git.push
            gate: push
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
          - kind: shorebird.release
            if: flavor.shorebird
          - kind: build.android
            if: platform == 'android' && !flavor.shorebird
          - kind: build.ios
            if: platform == 'ios' && !flavor.shorebird
  - name: upload
    jobs:
      upload:
        name: Upload ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        if: >-
          (platform == 'android' && flavor.credentials.play_sa)
          || (platform == 'ios' && inputs.appleAppIds[flavor.name])
        steps:
          - kind: upload.play
            if: platform == 'android'
          - kind: upload.appStore
            if: platform == 'ios'
            gate: store_submission
  - name: never
    jobs:
      none:
        if: "false"
        steps:
          - kind: command
''';

const app = AppProfile(
  name: 'mataa',
  path: '.',
  version: '5.4.1+3283',
  hasIos: true,
  hasAndroid: true,
  flavors: [
    FlavorProfile(
      name: 'prod',
      entrypoint: 'lib/main_prod.dart',
      shorebird: true,
      prod: true,
    ),
    FlavorProfile(name: 'dev', entrypoint: 'lib/main_dev.dart'),
  ],
);

const mataa = Project(
  id: 'prj_1',
  host: 'github.com',
  sourceKey: '1',
  githubRepoId: 1,
  fullName: 'acme/mataa',
  remote: 'git@github.com:acme/mataa.git',
  defaultBaseBranch: 'main',
  profile: ProjectProfile(apps: [app]),
);

Runner runner(
  String id, {
  List<String> capabilities = const ['android', 'flutter'],
  int slots = 4,
  List<String> jobIds = const [],
  RunnerStatus status = RunnerStatus.online,
}) => Runner(
  id: id,
  name: id,
  status: status,
  capabilities: capabilities,
  slots: slots,
  jobIds: jobIds,
  createdAt: at,
);

const playKey = Credential(
  id: 'crd_1',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.playSa,
  status: CredentialStatus.verified,
);

const otherAppKey = Credential(
  id: 'crd_2',
  projectId: 'prj_1',
  app: 'apps/x',
  flavor: 'prod',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
);

void main() {
  group('DispatchPreview.plan', () {
    test('expands, places and gates a production release', () {
      final linux = runner('linux', jobIds: ['a', 'b']);
      final mac = runner(
        'mac',
        capabilities: ['android', 'flutter', 'ios-sign'],
        slots: 3,
        jobIds: ['c'],
      );
      final preview = DispatchPreview.plan(
        project: mataa,
        workflow: WorkflowOutline.parse(releaseYaml),
        request: const DispatchRequest(
          inputs: {
            'appleAppIds': {'prod': '123'},
          },
        ),
        runners: [
          runner('gone', status: RunnerStatus.offline),
          runner('empty', slots: 0),
          linux,
          mac,
        ],
        gates: const ProjectGates({'push': false}),
        credentials: const [playKey, otherAppKey],
      );
      expect(
        preview,
        isNot(const DispatchPreview(flavors: [], platforms: [], stages: [])),
      );
      expect(preview.flavors, ['prod']);
      expect(preview.platforms, ['android', 'ios']);
      expect(preview.currentVersion, '5.4.1+3283');
      expect(preview.version, '5.4.1');
      expect(preview.jobCount, 5);
      expect(preview.gates, ['prod_release', 'store_submission']);
      expect(preview.stages, [
        const PreviewStage(
          name: 'prepare',
          gates: ['prod_release'],
          jobs: [
            PreviewJob(
              name: 'Prepare prod',
              flavor: 'prod',
              capabilities: [],
              engineOnly: true,
            ),
          ],
        ),
        PreviewStage(
          name: 'build',
          jobs: [
            PreviewJob(
              name: 'Build prod for android',
              flavor: 'prod',
              platform: 'android',
              capabilities: const ['android', 'flutter'],
              engineOnly: false,
              runner: mac,
              slot: 2,
            ),
            PreviewJob(
              name: 'Build prod for ios',
              flavor: 'prod',
              platform: 'ios',
              capabilities: const ['flutter', 'ios-sign'],
              engineOnly: false,
              runner: mac,
              slot: 3,
            ),
          ],
        ),
        const PreviewStage(
          name: 'upload',
          gates: ['store_submission'],
          jobs: [
            PreviewJob(
              name: 'Upload prod for android',
              flavor: 'prod',
              platform: 'android',
              capabilities: [],
              engineOnly: true,
            ),
            PreviewJob(
              name: 'Upload prod for ios',
              flavor: 'prod',
              platform: 'ios',
              capabilities: ['ios-sign'],
              engineOnly: true,
            ),
          ],
        ),
      ]);
    });

    test('an App Store upload with an API key needs no Mac', () {
      const ascKey = Credential(
        id: 'crd_3',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.verified,
      );

      final preview = DispatchPreview.plan(
        project: mataa,
        workflow: WorkflowOutline.parse(releaseYaml),
        request: const DispatchRequest(
          inputs: {
            'appleAppIds': {'prod': '123'},
          },
        ),
        runners: const [],
        gates: const ProjectGates({}),
        credentials: const [playKey, ascKey],
      );

      final upload = preview.stages
          .firstWhere((stage) => stage.name == 'upload')
          .jobs
          .firstWhere((job) => job.platform == 'ios');
      expect(upload.capabilities, isEmpty);
    });

    test('takes what the request asks and reads leniently', () {
      final full = runner('full', slots: 1, jobIds: ['a']);
      final preview = DispatchPreview.plan(
        project: mataa,
        workflow: WorkflowOutline.parse(r'''
stages:
  - name: build
    jobs:
      build:
        name: ${{ a = }}
        matrix:
          flavor: ${{ flavors }}
          platform: [android]
        if: "a ="
        steps:
          - kind: build.android
          - kind: test
            if: "("
      odd:
        matrix:
          flavor: 3
        steps: []
      broken:
        matrix:
          flavor: ${{ flavors[ }}
        steps: []
      lone:
        capabilities: [swift-linux]
        steps:
          - kind: shorebird.patch
'''),
        request: const DispatchRequest(
          app: '.',
          flavors: ['dev', 'ghost'],
          platforms: ['android'],
          bump: VersionBump.minor,
        ),
        runners: [full],
        gates: const ProjectGates({}),
        credentials: const [],
      );
      expect(preview.flavors, ['dev']);
      expect(preview.platforms, ['android']);
      expect(preview.version, '5.5.0');
      expect(preview.stages.single.jobs, const [
        PreviewJob(
          name: 'build (dev, android)',
          flavor: 'dev',
          platform: 'android',
          capabilities: ['android', 'flutter'],
          engineOnly: true,
        ),
        PreviewJob(
          name: 'lone',
          capabilities: ['android', 'flutter', 'swift-linux'],
          engineOnly: false,
        ),
      ]);
    });

    test('takes the only flavor and the version asked for', () {
      const single = Project(
        id: 'prj_2',
        host: 'github.com',
        sourceKey: '2',
        githubRepoId: 2,
        fullName: 'acme/one',
        remote: 'r',
        defaultBaseBranch: 'main',
        profile: ProjectProfile(
          apps: [
            AppProfile(
              name: 'one',
              path: 'apps/one',
              hasIos: true,
              flavors: [
                FlavorProfile(
                  name: 'default',
                  entrypoint: 'lib/main.dart',
                  implicit: true,
                ),
              ],
            ),
          ],
        ),
      );
      final preview = DispatchPreview.plan(
        project: single,
        workflow: WorkflowOutline.parse('lock: project\nstages: []\n'),
        request: const DispatchRequest(app: 'apps/x', version: '2.0.0'),
        runners: const [],
        gates: const ProjectGates({}),
        credentials: const [],
      );
      expect(preview.flavors, ['default']);
      expect(preview.platforms, ['ios']);
      expect(preview.version, '2.0.0');
      expect(preview.currentVersion, isNull);
      expect(preview.jobCount, 0);
      expect(preview.gates, isEmpty);
    });

    test('is empty for a project without an app', () {
      final preview = DispatchPreview.plan(
        project: project,
        workflow: const WorkflowOutline(),
        request: const DispatchRequest(),
        runners: const [],
        gates: const ProjectGates({}),
        credentials: const [],
      );
      expect(
        preview,
        const DispatchPreview(flavors: [], platforms: [], stages: []),
      );
    });
  });

  group('bumpVersion', () {
    test('bumps the version of the pubspec', () {
      expect(bumpVersion('5.4.1+3283', null), '5.4.1');
      expect(bumpVersion('5.4.1+3283', VersionBump.keep), '5.4.1');
      expect(bumpVersion('5.4.1', VersionBump.patch), '5.4.2');
      expect(bumpVersion('5.4.1', VersionBump.minor), '5.5.0');
      expect(bumpVersion('5.4.1', VersionBump.major), '6.0.0');
    });

    test('is null without a version', () {
      expect(bumpVersion(null, VersionBump.patch), isNull);
      expect(bumpVersion('next', VersionBump.patch), isNull);
    });
  });
}
