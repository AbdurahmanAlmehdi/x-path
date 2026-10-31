import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/all_steps.dart';
import '../../helpers/dispatch_harness.dart';
import '../../helpers/workflow_fixtures.dart';

/// A workflow with one job, matrix [matrix] and [steps] (YAML lines, indented
/// by the caller to ten spaces).
String _workflow(String steps, {String matrix = '', String inputs = ''}) =>
    '''
schema: 1
$inputs
stages:
  - name: only
    jobs:
      job:
$matrix
        steps:
$steps
''';

const _flavorMatrix = r'''
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
''';

Matcher _fails(Object message) => throwsA(
  isA<DispatchException>().having((e) => e.message, 'message', message),
);

/// Saving the workflow fails: validation finds the issue before a dispatch.
Matcher _invalid(Object message) => throwsA(
  isA<WorkflowInvalidException>().having(
    (e) => e.issues.single.message,
    'issue',
    message,
  ),
);

void main() {
  late DispatchHarness harness;

  setUp(() async => harness = await DispatchHarness.create());

  Future<Run> dispatch(
    String steps, {
    String matrix = '',
    String inputs = '',
    DispatchRequest request = const DispatchRequest(),
  }) => harness.dispatchCustom(
    _workflow(steps, matrix: matrix, inputs: inputs),
    request,
  );

  test('refuses a GitHub step for a project that is not on GitHub', () async {
    // The dispatcher refuses these first (ADR 0015); the planners say so too.
    const mirror = GitMirror(key: 'h0123456789abcdef', path: '/m');
    final run = RunContext(
      runId: 'run_1',
      project: ProjectRecord(
        id: 'prj_1',
        host: 'bitbucket.org',
        sourceKey: 'h0123456789abcdef',
        fullName: 'ws/demo',
        remote: 'git@bitbucket.org:ws/demo.git',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(apps: [demoApp]),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
      app: demoApp,
      flavors: demoApp.flavors,
      platforms: const ['android'],
      ref: 'main',
      sha: 'a' * 40,
      mirror: mirror,
      model: const ReleaseModel(),
      worktreeAt: (_, name) => '/w/$name',
      inputs: const {},
      bump: 'keep',
      version: AppVersion.parse('1.2.4+9'),
      build: 9,
      release: 'rel_1',
    );

    for (final kind in ['github.createPr', 'github.mergePr']) {
      await expectLater(
        StepPlanners(allSteps()).plan(
          StepPlanning(
            kind: kind,
            job: JobContext(
              run: run,
              jobId: 'job_1',
              worktree: const ReleaseWorktree(
                path: '/w',
                mirror: mirror,
                sha: 'a',
              ),
              flavorValue: null,
            ),
            values: const {},
            position: const SourcePosition(7, 3),
          ),
        ),
        _fails(
          'Line 7, $kind: ws/demo is not on GitHub, so it has no pull '
          'request.',
        ),
        reason: kind,
      );
    }
  });

  group('the catalog', () {
    test('lists the step types a workflow can use, and what each takes', () {
      final planners = StepPlanners(allSteps());

      expect(planners.kinds, [
        'analyze',
        'build.android',
        'build.ios',
        'build.verifyCompiledConfig',
        'command',
        'git.checkout',
        'git.push',
        'git.releaseBranch',
        'git.tag',
        'github.createPr',
        'github.mergePr',
        'guard',
        'ios.stripAndReexport',
        'record.manifest',
        'shorebird.patch',
        'shorebird.release',
        'shorebird.track',
        'store.rollout',
        'symbols.archive',
        'test',
        'upload.appStore',
        'upload.firebase',
        'upload.play',
        'version.bump',
      ]);
      expect(planners.withKeys('guard'), {'checks', 'credentialKinds'});
      expect(planners.withKeys('version.bump'), isEmpty);
      expect(planners.withKeys('gate'), isNull, reason: 'gate: is not a step');
      expect(planners.withKeys('nope'), isNull);
    });

    test('every step type describes itself and types its keys (UX-02)', () {
      final planners = StepPlanners(allSteps());

      expect(stepAbout.keys.toSet(), planners.kinds.toSet());
      for (final kind in planners.kinds) {
        final type = planners.describe(kind)!;
        expect(type.title, isNotEmpty, reason: kind);
        expect(type.description, isNotEmpty, reason: kind);
        expect(
          type.group,
          isIn(['Source', 'Checks', 'Build', 'Upload', 'GitHub', 'Other']),
          reason: kind,
        );
        expect(type.withKeys, [...type.withKeys]..sort(), reason: kind);
        for (final key in type.keys) {
          expect(key.type, isNot(StepKeyType.any), reason: '$kind.${key.name}');
          expect(key.description, isNotEmpty, reason: '$kind.${key.name}');
        }
      }
      expect(planners.describe('nope'), isNull);
    });

    test('says what a runner needs for each step type', () {
      final planners = StepPlanners(allSteps());

      expect(planners.describe('build.android')!.capabilities, [
        ['android', 'flutter'],
      ]);
      expect(planners.describe('shorebird.release')!.capabilities, [
        ['flutter', 'android'],
        ['flutter', 'ios-sign'],
      ]);
      expect(planners.describe('upload.firebase')!.capabilities, isEmpty);
    });

    test('says which keys a step type needs and what each holds', () {
      final planners = StepPlanners(allSteps());

      final ios = planners.keysOf('build.ios')!;
      expect(ios['exportOptionsPlist']!.required, isTrue);
      expect(ios['obfuscate']!.value, StepValue.flag);
      expect(planners.keysOf('build.android')!['artifact']!.options, [
        'apk',
        'aab',
      ]);
      expect(
        planners.keysOf('guard')!['checks']!.options,
        contains('versionSync'),
      );
      expect(
        planners.keysOf('guard')!['credentialKinds']!.options,
        contains('play_sa'),
      );
      expect(planners.keysOf('nope'), isNull);
      for (final kind in planners.kinds) {
        expect(
          planners.keysOf(kind)!.keys.toSet(),
          planners.withKeys(kind),
          reason: kind,
        );
      }
    });

    test('says when the engine cannot run a step type', () async {
      final planners = StepPlanners(StepRegistry(const []));

      expect(
        () => planners.gate(action: GateAction.push, projectId: 'p', sha: 's'),
        _fails('This engine cannot run steps of type "gate".'),
      );
    });
  });

  group('command', () {
    test('runs in the app folder unless told otherwise', () async {
      final run = await dispatch('''
          - kind: command
            with:
              executable: echo
              arguments: [hi]
              environment: {A: b}
              passThroughEnvironment: [HOME]
              secretEnvironment: {S: key}
              secretFiles: {F: key}
              sideEffect: true
          - kind: command
            with:
              executable: ls
              workingDirectory: lib
''');

      final job = await harness.job(run.jobs.single.id);
      final first = await harness.input(job, 'command');
      final second = await harness.input(job, 'command', nth: 1);
      expect(first['executable'], 'echo');
      expect(first['arguments'], ['hi']);
      expect(first['workingDirectory'], '/data/worktrees/42/${job.id}');
      expect(first['sideEffect'], isTrue);
      expect(second['workingDirectory'], '/data/worktrees/42/${job.id}/lib');
      expect(job.steps.first.sideEffect, isTrue);
    });

    test('runs in the folder of the app in a monorepo', () async {
      harness = await DispatchHarness.create(
        apps: [
          AppProfile(
            name: 'second',
            path: 'apps/second',
            hasAndroid: true,
            version: '1.0.0+1',
            flavors: demoApp.flavors,
          ),
        ],
      );
      harness.pubspec.files['apps/second/pubspec.yaml'] = 'version: 1.0.0+1\n';

      final run = await dispatch('''
          - kind: command
            with:
              executable: pwd
''');

      final job = await harness.job(run.jobs.single.id);
      expect(
        (await harness.input(job, 'command'))['workingDirectory'],
        '/data/worktrees/42/${job.id}/apps/second',
      );
    });

    test('needs an executable and a folder inside the app', () async {
      await expectLater(
        dispatch('''
          - kind: command
'''),
        _invalid('"command" needs "executable" under "with".'),
      );
      for (final directory in ['/etc', '../x']) {
        await expectLater(
          dispatch('''
          - kind: command
            with:
              executable: ls
              workingDirectory: $directory
'''),
          _fails(
            endsWith('"workingDirectory" must be a folder inside the app.'),
          ),
        );
      }
    });

    test('says which value is of the wrong type', () async {
      for (final (with_, message) in [
        ('executable: 3', '"executable" must be a string.'),
        (
          'executable: ls\n              arguments: 3',
          '"arguments" must be a list of strings.',
        ),
        (
          'executable: ls\n              arguments: [1]',
          '"arguments" must be a list of strings.',
        ),
        (
          'executable: ls\n              sideEffect: maybe',
          '"sideEffect" must be true or false.',
        ),
        (
          'executable: ls\n              environment: [a]',
          '"environment" must be a mapping of strings.',
        ),
        (
          'executable: ls\n              environment: {a: 1}',
          '"environment" must be a mapping of strings.',
        ),
      ]) {
        await expectLater(
          dispatch('''
          - kind: command
            with:
              $with_
'''),
          _invalid(message),
          reason: with_,
        );
      }
    });
  });

  group('git.checkout', () {
    test('cannot start from a job that has none in this run', () async {
      await expectLater(
        harness.dispatchCustom(r'''
schema: 1
stages:
  - name: a
    jobs:
      prepare:
        if: platform == 'ios'
        matrix:
          platform: ${{ platforms }}
        steps:
          - kind: git.checkout
  - name: b
    jobs:
      build:
        matrix:
          platform: ${{ platforms }}
        steps:
          - kind: git.checkout
            with:
              commitFrom: prepare
''', const DispatchRequest(platforms: ['android'])),
        _fails(
          'Line 17, git.checkout: The job "prepare" has no job to start from '
          'here.',
        ),
      );
    });

    test('starts from the job of the same flavor, not of another', () async {
      final run = await harness.dispatchCustom(r'''
schema: 1
stages:
  - name: a
    jobs:
      prepare:
        matrix:
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
  - name: b
    jobs:
      build:
        matrix:
          flavor: ${{ flavors }}
        steps:
          - kind: git.checkout
            with:
              commitFrom: prepare
''', const DispatchRequest(flavors: ['dev', 'prod']));

      final jobs = await harness.jobsOf(run);
      final byName = {for (final job in jobs) job.name!: job};
      expect(byName.keys, [
        'prepare (dev)',
        'prepare (prod)',
        'build (dev)',
        'build (prod)',
      ]);
      expect(
        (await harness.input(
          byName['build (dev)']!,
          'git.checkout',
        ))['commitFromJob'],
        byName['prepare (dev)']!.id,
      );
      expect(
        (await harness.input(
          byName['build (prod)']!,
          'git.checkout',
        ))['commitFromJob'],
        byName['prepare (prod)']!.id,
      );
    });
  });

  group('the define file of the flavor', () {
    final secret = demoCredential(
      demoFlavor('prod'),
      CredentialKind.dartDefines,
    ).secretKey;

    Future<Map<String, Map<String, dynamic>>> inputs(String extra) async {
      final run = await dispatch(
        '''
          - kind: build.android
            with: {$extra}
          - kind: shorebird.release
            with: {$extra}
          - kind: shorebird.patch
            with: {$extra}
          - kind: build.verifyCompiledConfig
            with: {keys: [API], $extra}
          - kind: record.manifest
            with: {$extra}
          - kind: symbols.archive
            with: {$extra}
          - kind: ios.stripAndReexport
            with: {exportOptionsPlist: ios/Export.plist, frameworks: [Agora], $extra}
''',
        matrix: _flavorMatrix,
        request: const DispatchRequest(
          platforms: ['android'],
          flavors: ['prod'],
          releaseVersion: '1.2.0+30',
        ),
      );
      final job = await harness.job(run.jobs.single.id);
      return {
        for (final kind in const [
          'build.android',
          'shorebird.release',
          'shorebird.patch',
          'build.verifyCompiledConfig',
          'record.manifest',
          'symbols.archive',
          'ios.stripAndReexport',
        ])
          kind: await harness.input(job, kind),
      };
    }

    const users = [
      'build.android',
      'shorebird.release',
      'shorebird.patch',
      'build.verifyCompiledConfig',
      'record.manifest',
    ];

    setUp(() async {
      await harness.saveCredential('prod', CredentialKind.dartDefines);
    });

    test('reaches the steps that read it when no file is named', () async {
      final found = await inputs('');

      for (final kind in users) {
        expect(found[kind]!['dartDefineSecret'], secret, reason: kind);
        expect(found[kind]!.keys, isNot(contains('dartDefineFile')));
      }
    });

    test('stays away from the steps that do not read it', () async {
      final found = await inputs('');

      for (final kind in const ['symbols.archive', 'ios.stripAndReexport']) {
        expect(found[kind]!.keys, isNot(contains('dartDefineSecret')));
      }
    });

    test('stays away from a config check that reads no keys', () async {
      final run = await dispatch(
        '''
          - kind: build.verifyCompiledConfig
            with: {needles: [x]}
''',
        matrix: _flavorMatrix,
        request: const DispatchRequest(
          platforms: ['android'],
          flavors: ['prod'],
        ),
      );
      final input = await harness.input(
        await harness.job(run.jobs.single.id),
        'build.verifyCompiledConfig',
      );

      expect(input.keys, isNot(contains('dartDefineSecret')));
    });

    test('gives way to a file the workflow names', () async {
      final found = await inputs('dartDefineFile: env.json');

      for (final kind in users) {
        expect(found[kind]!['dartDefineFile'], 'env.json', reason: kind);
        expect(found[kind]!.keys, isNot(contains('dartDefineSecret')));
      }
    });
  });

  group('the build steps', () {
    test('pass the settings the workflow gives', () async {
      final run = await dispatch(
        '''
          - kind: build.android
            with:
              artifact: aab
              dartDefineFile: env.json
              obfuscate: true
          - kind: build.ios
            with:
              exportOptionsPlist: ios/Export.plist
          - kind: ios.stripAndReexport
            with:
              exportOptionsPlist: ios/Export.plist
              frameworks: [Agora]
          - kind: build.verifyCompiledConfig
            with:
              keys: [API_URL]
              dartDefineFile: env.json
              needles: [example.com]
              artifactName: custom.apk
''',
        matrix: _flavorMatrix,
        request: const DispatchRequest(
          platforms: ['android'],
          flavors: ['prod'],
        ),
      );

      final job = await harness.job(run.jobs.single.id);
      final android = await harness.input(job, 'build.android');
      expect(android['artifact'], 'aab');
      expect(android['dartDefineFile'], 'env.json');
      expect(android['obfuscate'], isTrue);
      expect(android['flavor'], 'prod');
      final strip = await harness.input(job, 'ios.stripAndReexport');
      expect(strip['frameworks'], ['Agora']);
      final verify = await harness.input(job, 'build.verifyCompiledConfig');
      expect(verify['artifactName'], 'custom.apk');
      expect(verify['keys'], ['API_URL']);
      expect(verify['needles'], ['example.com']);
      expect(run.jobs.single.capabilities, ['android', 'flutter', 'ios-sign']);
    });

    test(
      'name the artifact of the platform for the compiled config check',
      () async {
        final ios = await dispatch(
          '''
          - kind: build.verifyCompiledConfig
            with:
              needles: [x]
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(platforms: ['ios'], flavors: ['dev']),
        );
        final android = await dispatch(
          '''
          - kind: build.verifyCompiledConfig
            with:
              needles: [x]
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(
            platforms: ['android'],
            flavors: ['dev'],
          ),
        );

        expect(
          (await harness.input(
            await harness.job(ios.jobs.single.id),
            'build.verifyCompiledConfig',
          ))['artifactName'],
          startsWith('dev-1.2.3+'),
        );
        expect(
          (await harness.input(
            await harness.job(ios.jobs.single.id),
            'build.verifyCompiledConfig',
          ))['artifactName'],
          endsWith('.ipa'),
        );
        expect(
          (await harness.input(
            await harness.job(android.jobs.single.id),
            'build.verifyCompiledConfig',
          ))['artifactName'],
          endsWith('.apk'),
        );
      },
    );

    test('need an export options file for iOS', () async {
      await expectLater(
        dispatch('''
          - kind: build.ios
'''),
        _invalid('"build.ios" needs "exportOptionsPlist" under "with".'),
      );
    });

    test(
      'say when the app has no build number and the run allocates none',
      () async {
        harness = await DispatchHarness.create(pubspecVersion: '1.2.3');

        for (final step in [
          'build.android',
          'record.manifest',
          'git.tag',
          'git.push',
        ]) {
          await expectLater(
            dispatch('''
          - kind: $step
'''),
            _fails(
              allOf(
                contains(step),
                contains('The app has no build number'),
                contains('add a "version.bump" step'),
              ),
            ),
            reason: step,
          );
        }
      },
    );

    test(
      'use the build number of the pubspec when the run allocates none',
      () async {
        final run = await dispatch(
          '''
          - kind: build.android
          - kind: record.manifest
          - kind: git.tag
          - kind: git.push
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(
            platforms: ['android'],
            flavors: ['dev'],
          ),
        );

        final job = await harness.job(run.jobs.single.id);
        expect(
          (await harness.input(job, 'build.android'))['version'],
          '1.2.3+45',
        );
        expect((await harness.input(job, 'git.tag'))['name'], 'v1.2.3+45');
        final push = await harness.input(job, 'git.push');
        expect(push.containsKey('branch'), isFalse);
        expect(push['tag'], 'v1.2.3+45');
      },
    );
  });

  group('shorebird', () {
    const patchSteps = '''
          - kind: shorebird.release
            with:
              platform: android
              artifact: aab
              keystore: false
          - kind: shorebird.patch
            with:
              platform: ios
              exportOptionsPlist: ios/Export.plist
''';

    test('takes the platform of the step, whatever the job has', () async {
      await harness.saveCredential('prod', CredentialKind.keystore);

      final run = await dispatch(
        patchSteps,
        matrix: r'''
        matrix:
          flavor: ${{ flavors }}
''',
        request: const DispatchRequest(
          flavors: ['prod'],
          releaseVersion: '1.2.0+30',
        ),
      );

      final job = await harness.job(run.jobs.single.id);
      final release = await harness.input(job, 'shorebird.release');
      expect(release['platform'], 'android');
      expect(release['artifact'], 'aab');
      expect(
        release['secretFiles'],
        isEmpty,
        reason: 'keystore: false leaves the keystore out',
      );
      final patch = await harness.input(job, 'shorebird.patch');
      expect(patch['platform'], 'ios');
      expect(patch['exportOptionsPlist'], 'ios/Export.plist');
      expect(run.jobs.single.capabilities, ['android', 'flutter', 'ios-sign']);
    });

    test('needs a platform from the job or the step', () async {
      await expectLater(
        dispatch('''
          - kind: shorebird.release
'''),
        _fails(contains('"platform" must be android or ios')),
      );
      await expectLater(
        dispatch('''
          - kind: shorebird.patch
            with:
              platform: windows
''', request: const DispatchRequest(releaseVersion: '1.2.0+30')),
        _invalid('"platform" takes android, ios.'),
      );
    });

    test(
      'finds the Shorebird app id in the flavor or in shorebird.yaml',
      () async {
        AppProfile app({String? flavorId, ShorebirdProfile? shorebird}) =>
            AppProfile(
              name: 'demo',
              path: '.',
              hasAndroid: true,
              version: '1.2.3+45',
              shorebird: shorebird,
              flavors: [
                FlavorProfile(
                  name: 'prod',
                  entrypoint: 'lib/main.dart',
                  shorebirdAppId: flavorId,
                  prod: true,
                ),
              ],
            );
        const steps = '''
          - kind: shorebird.release
            with:
              platform: android
''';
        const request = DispatchRequest(
          platforms: ['android'],
          flavors: ['prod'],
        );
        for (final (profile, expected) in <(AppProfile, String?)>[
          (app(flavorId: 'from-flavor'), 'from-flavor'),
          (
            app(
              shorebird: const ShorebirdProfile(
                appId: 'from-yaml',
                flavorAppIds: {'prod': 'from-yaml-flavor'},
              ),
            ),
            'from-yaml-flavor',
          ),
          (
            app(shorebird: const ShorebirdProfile(appId: 'from-yaml')),
            'from-yaml',
          ),
          (app(), null),
        ]) {
          harness = await DispatchHarness.create(apps: [profile]);
          if (expected == null) {
            await expectLater(
              dispatch(steps, matrix: _flavorMatrix, request: request),
              _fails(contains('The flavor has no Shorebird app id')),
            );
          } else {
            final run = await dispatch(
              steps,
              matrix: _flavorMatrix,
              request: request,
            );
            final job = await harness.job(run.jobs.single.id);
            expect(
              (await harness.input(job, 'shorebird.release'))['shorebirdAppId'],
              expected,
            );
          }
        }
      },
    );

    test('can be told the app id', () async {
      final run = await dispatch('''
          - kind: shorebird.patch
            with:
              platform: android
              shorebirdAppId: sb-explicit
''', request: const DispatchRequest(releaseVersion: '1.2.0+30'));

      final job = await harness.job(run.jobs.single.id);
      expect(
        (await harness.input(job, 'shorebird.patch'))['shorebirdAppId'],
        'sb-explicit',
      );
    });

    test('patch needs the app id too', () async {
      harness = await DispatchHarness.create(
        apps: [
          const AppProfile(
            name: 'demo',
            path: '.',
            hasAndroid: true,
            version: '1.2.3+45',
            flavors: [
              FlavorProfile(
                name: 'prod',
                entrypoint: 'lib/main.dart',
                prod: true,
              ),
            ],
          ),
        ],
      );

      await expectLater(
        dispatch('''
          - kind: shorebird.patch
            with:
              platform: android
''', request: const DispatchRequest(releaseVersion: '1.2.0+30')),
        _fails(contains('The flavor has no Shorebird app id')),
      );
    });
  });

  group('the uploads', () {
    test('take the options of the store', () async {
      await harness.saveCredential('prod', CredentialKind.playSa);

      final run = await dispatch(
        '''
          - kind: version.bump
          - kind: upload.play
            with:
              artifactName: custom.aab
              packageName: ly.other
              track: production
              status: inProgress
              userFraction: 0.1
              releaseName: Spring
              releaseNotes: {en-US: Hello, ar: Marhaba}
''',
        matrix: _flavorMatrix,
        request: const DispatchRequest(
          platforms: ['android'],
          flavors: ['prod'],
        ),
      );

      final play = await harness.input(
        await harness.job(run.jobs.single.id),
        'upload.play',
      );
      expect(play, {
        'artifactName': 'custom.aab',
        'packageName': 'ly.other',
        'version': '1.2.3+1',
        'serviceAccountSecret': 'credential.prod.play_sa',
        'track': 'production',
        'status': 'inProgress',
        'userFraction': 0.1,
        'releaseName': 'Spring',
        'releaseNotes': {'en-US': 'Hello', 'ar': 'Marhaba'},
      });
    });

    test(
      'to App Store Connect need a Mac only for an Apple ID (altool)',
      () async {
        await harness.saveCredential('prod', CredentialKind.ascKey);
        await harness.saveCredential(
          'dev',
          CredentialKind.appleId,
          account: 'dev@example.com',
        );
        const steps = '''
          - kind: version.bump
          - kind: upload.appStore
            with:
              appleAppId: "1"
''';

        final apiKey = await dispatch(
          steps,
          matrix: _flavorMatrix,
          request: const DispatchRequest(platforms: ['ios'], flavors: ['prod']),
        );
        final appleId = await dispatch(
          steps,
          matrix: _flavorMatrix,
          request: const DispatchRequest(platforms: ['ios'], flavors: ['dev']),
        );

        expect(apiKey.jobs.single.capabilities, isEmpty);
        expect(appleId.jobs.single.capabilities, ['ios-sign']);
      },
    );

    test('take their file from the build job of the same cell', () async {
      await harness.saveCredential('dev', CredentialKind.playSa);
      await harness.saveCredential('dev', CredentialKind.firebaseSa);
      await harness.saveCredential('dev', CredentialKind.ascKey);

      final run = await harness.dispatchCustom(r'''
schema: 1
stages:
  - name: build
    jobs:
      build:
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: version.bump
  - name: upload
    jobs:
      upload:
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: upload.play
            if: platform == 'android'
            with:
              artifactsFrom: build
          - kind: upload.firebase
            if: platform == 'android'
            with:
              artifactsFrom: build
              appId: 1:684690133351:android:b434734f585770367c1fc2
          - kind: upload.appStore
            if: platform == 'ios'
            with:
              artifactsFrom: build
              appleAppId: "123"
''', const DispatchRequest(platforms: ['android', 'ios'], flavors: ['dev']));

      final jobs = await harness.jobsOf(run);
      final byName = {for (final job in jobs) job.name!: job};
      expect(byName.keys, [
        'build (android, dev)',
        'build (ios, dev)',
        'upload (android, dev)',
        'upload (ios, dev)',
      ]);
      final android = byName['upload (android, dev)']!;
      final ios = byName['upload (ios, dev)']!;
      expect(
        (await harness.input(android, 'upload.play'))['artifactJob'],
        byName['build (android, dev)']!.id,
      );
      expect(
        (await harness.input(android, 'upload.firebase'))['artifactJob'],
        byName['build (android, dev)']!.id,
      );
      expect(
        (await harness.input(ios, 'upload.appStore'))['artifactJob'],
        byName['build (ios, dev)']!.id,
      );
    });

    test('say when no job of this cell has the file to take', () async {
      await harness.saveCredential('dev', CredentialKind.playSa);

      await expectLater(
        harness.dispatchCustom(r'''
schema: 1
stages:
  - name: build
    jobs:
      build:
        if: platform == 'ios'
        matrix:
          platform: ${{ platforms }}
        steps:
          - kind: version.bump
  - name: upload
    jobs:
      upload:
        matrix:
          platform: ${{ platforms }}
          flavor: ${{ flavors }}
        steps:
          - kind: upload.play
            with:
              artifactsFrom: build
''', const DispatchRequest(platforms: ['android'], flavors: ['dev'])),
        _fails(
          contains(
            'upload.play: The job "build" has no job to take the artifact '
            'from here.',
          ),
        ),
      );
    });

    test('cannot take their file from a job that is not earlier', () async {
      await expectLater(
        dispatch('''
          - kind: upload.play
            with:
              artifactsFrom: job
'''),
        throwsA(isA<WorkflowInvalidException>()),
      );
    });

    test('need the credential, the ids and valid values', () async {
      await expectLater(
        dispatch(
          '''
          - kind: upload.play
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(
            platforms: ['android'],
            flavors: ['dev'],
          ),
        ),
        throwsA(
          isA<DispatchException>()
              .having(
                (e) => e.message,
                'message',
                contains('has no play_sa credential assigned'),
              )
              .having(
                (e) => e.hint,
                'hint',
                'Add a Google Play service account credential and assign it '
                    'to dev, then dispatch again.',
              )
              .having((e) => e.details, 'details', {
                'reason': ErrorReason.credentialUnassigned,
                'kind': 'play_sa',
                'flavor': 'dev',
              }),
        ),
      );
      await harness.saveCredential('dev', CredentialKind.playSa);
      await expectLater(
        dispatch(
          '''
          - kind: upload.play
            with:
              userFraction: lots
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(
            platforms: ['android'],
            flavors: ['dev'],
          ),
        ),
        _invalid('"userFraction" must be a number.'),
      );
      await expectLater(
        dispatch(
          '''
          - kind: upload.play
            with:
              userFraction: 2
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(
            platforms: ['android'],
            flavors: ['dev'],
          ),
        ),
        _fails(
          allOf(
            startsWith('Line 12, upload.play: '),
            contains('"userFraction" must be above 0 and below 1.'),
          ),
        ),
      );
    });

    test('need an application id and a bundle id to upload to', () async {
      const noIds = AppProfile(
        name: 'demo',
        path: '.',
        hasAndroid: true,
        hasIos: true,
        version: '1.2.3+45',
        flavors: [FlavorProfile(name: 'dev', entrypoint: 'lib/main.dart')],
      );
      harness = await DispatchHarness.create(apps: [noIds]);
      await harness.saveCredential('dev', CredentialKind.playSa);
      await harness.saveCredential('dev', CredentialKind.ascKey);

      await expectLater(
        dispatch('''
          - kind: upload.play
''', matrix: _flavorMatrix),
        _fails(contains('The flavor has no Android application id.')),
      );
      await expectLater(
        dispatch('''
          - kind: upload.appStore
            with:
              appleAppId: "1"
''', matrix: _flavorMatrix),
        _fails(contains('The flavor has no iOS bundle id.')),
      );
    });

    test('are refused by the step when a value is not valid', () async {
      await harness.saveCredential('dev', CredentialKind.firebaseSa);

      await expectLater(
        dispatch(
          '''
          - kind: upload.firebase
            with:
              appId: not-an-app-id
''',
          matrix: _flavorMatrix,
          request: const DispatchRequest(
            platforms: ['android'],
            flavors: ['dev'],
          ),
        ),
        _fails(
          allOf(
            startsWith('Line 12, upload.firebase: '),
            contains('"appId" must be a Firebase app id'),
          ),
        ),
      );
    });
  });

  group('the release steps', () {
    test('need a version that this run bumps', () async {
      await expectLater(
        dispatch('''
          - kind: git.releaseBranch
'''),
        _fails(
          'Line 9, git.releaseBranch: There is no release version: this run '
          'bumps none.',
        ),
      );
    });

    test('push the branch or the tag as told', () async {
      final run = await dispatch('''
          - kind: version.bump
          - kind: git.push
            with:
              branch: false
          - kind: git.push
            with:
              tag: false
''');

      final job = await harness.job(run.jobs.single.id);
      final tagOnly = await harness.input(job, 'git.push');
      final branchOnly = await harness.input(job, 'git.push', nth: 1);
      expect(tagOnly.containsKey('branch'), isFalse);
      expect(tagOnly['tag'], 'v1.2.3+1');
      expect(branchOnly['branch'], 'release/1.2.3');
      expect(branchOnly.containsKey('tag'), isFalse);
    });

    test(
      'tag with the app and flavor of the release model when it says so',
      () async {
        final run = await dispatch(
          '''
          - kind: version.bump
          - kind: git.tag
          - kind: git.releaseBranch
''',
          matrix: r'''
        matrix:
          flavor: ${{ flavors }}
''',
          request: const DispatchRequest(flavors: ['dev']),
        );

        final job = await harness.job(run.jobs.single.id);
        expect((await harness.input(job, 'git.tag'))['name'], 'v1.2.3+1');
        final branch = await harness.input(job, 'git.releaseBranch');
        expect(branch['version'], '1.2.3');
      },
    );
  });

  group('the test steps', () {
    test('take the failOn level', () async {
      final run = await dispatch('''
          - kind: analyze
            with:
              failOn: warning
''');

      expect(
        (await harness.input(
          await harness.job(run.jobs.single.id),
          'analyze',
        ))['failOn'],
        'warning',
      );
    });
  });

  group('the values of a step', () {
    test('keep their type through the placeholders', () async {
      final run = await dispatch(
        r'''
          - kind: build.android
            with:
              obfuscate: ${{ inputs.flag }}
              artifact: ${{ inputs.kind }}
''',
        inputs: '''
inputs:
  flag:
    default: true
  kind:
    default: aab
''',
        matrix: _flavorMatrix,
        request: const DispatchRequest(
          platforms: ['android'],
          flavors: ['dev'],
        ),
      );

      final build = await harness.input(
        await harness.job(run.jobs.single.id),
        'build.android',
      );
      expect(build['obfuscate'], isTrue);
      expect(build['artifact'], 'aab');
    });

    test('are dropped when a placeholder gives null', () async {
      final run = await dispatch(
        r'''
          - kind: build.android
            with:
              dartDefineFile: ${{ inputs.file }}
''',
        inputs: '''
inputs:
  file:
''',
        matrix: _flavorMatrix,
        request: const DispatchRequest(
          platforms: ['android'],
          flavors: ['dev'],
        ),
      );

      final build = await harness.input(
        await harness.job(run.jobs.single.id),
        'build.android',
      );
      expect(build.containsKey('dartDefineFile'), isFalse);
    });

    test('can be resolved inside lists and maps', () async {
      final run = await dispatch(
        r'''
          - kind: command
            with:
              executable: echo
              arguments: ["a-${{ inputs.x }}", "b"]
              environment: {K: "${{ inputs.x }}"}
''',
        inputs: '''
inputs:
  x:
    default: "1"
''',
      );

      final command = await harness.input(
        await harness.job(run.jobs.single.id),
        'command',
      );
      expect(command['arguments'], ['a-1', 'b']);
      expect(command['environment'], {'K': '1'});
    });
  });

  group('the matrix', () {
    test('says when a placeholder gives a platform the app lacks', () async {
      const steps = '''
          - kind: git.checkout
''';
      const matrix = r'''
        matrix:
          platform: ${{ inputs.platforms }}
''';
      const inputs = '''
inputs:
  platforms:
''';
      Future<Run> go(List<String> platforms) => dispatch(
        steps,
        matrix: matrix,
        inputs: inputs,
        request: DispatchRequest(inputs: {'platforms': platforms}),
      );

      await expectLater(
        go(['windows']),
        _fails('Line 8: unknown platform "windows".'),
      );
      harness = await DispatchHarness.create(
        apps: [
          AppProfile(
            name: 'demo',
            path: '.',
            hasAndroid: true,
            version: '1.2.3+45',
            flavors: demoApp.flavors,
          ),
        ],
      );
      await expectLater(
        go(['ios']),
        _fails('Line 8: the app has no ios project.'),
      );
      harness = await DispatchHarness.create(
        apps: [
          AppProfile(
            name: 'demo',
            path: '.',
            hasIos: true,
            version: '1.2.3+45',
            flavors: demoApp.flavors,
          ),
        ],
      );
      await expectLater(
        go(['android']),
        _fails('Line 8: the app has no android project.'),
      );
    });

    test('says when a placeholder gives a flavor the app lacks', () async {
      await expectLater(
        dispatch(
          '''
          - kind: git.checkout
''',
          matrix: r'''
        matrix:
          flavor: ${{ inputs.flavors }}
''',
          inputs: '''
inputs:
  flavors:
''',
          request: const DispatchRequest(
            inputs: {
              'flavors': ['qa'],
            },
          ),
        ),
        _fails('Line 8: the app has no flavor "qa".'),
      );
    });
  });

  group('an unfinished dispatch', () {
    test('cancels the jobs it made when one cannot be stored', () async {
      final repository = _FailingJobs();
      harness = await DispatchHarness.create(jobRepository: repository);
      repository.failOnCreate = 2;

      await expectLater(
        harness.dispatchBuiltin('dev-build'),
        throwsA(isA<StateError>()),
      );

      final left = await repository.list(states: JobState.values.toSet());
      expect(left.map((job) => job.state), [JobState.cancelled]);
    });
  });

  group('the dispatcher and the service without a fixed random source', () {
    test('make their own ids', () async {
      final workflows = WorkflowService(
        repository: InMemoryWorkflowRepository(),
        projects: harness.projects,
        catalog: harness.planners,
        events: harness.events,
        clock: ManualClock(DateTime.utc(2026)),
      );

      final id = (await workflows.create(
        'prj_1',
        name: 'own',
        yaml: _workflow('''
          - kind: git.checkout
'''),
      )).id;

      expect(id, matches(RegExp(r'^wf_[0-9a-f]{16}$')));
      harness = await DispatchHarness.create(seeded: false);
      final run = await harness.dispatchBuiltin('test');
      expect(run.id, matches(RegExp(r'^run_[0-9a-f]{16}$')));
    });
  });
}

/// A job repository that fails the Nth job it is asked to store.
class _FailingJobs extends InMemoryJobRepository {
  int? failOnCreate;
  var _created = 0;

  @override
  Future<void> create(JobRecord job, List<StepRecord> steps) async {
    if (++_created == failOnCreate) throw StateError('disk on fire');
    await super.create(job, steps);
  }
}
