import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/dispatch_harness.dart';
import '../../helpers/workflow_fixtures.dart';

Matcher _dispatchError(Object message) => throwsA(
  isA<DispatchException>().having((e) => e.message, 'message', message),
);

void main() {
  late DispatchHarness harness;

  setUp(() async => harness = await DispatchHarness.create());

  group('the dev-build workflow', () {
    test('makes one queued job per platform for the dev flavor', () async {
      final run = await harness.dispatchBuiltin('dev-build');

      expect(run.id, startsWith('run_'));
      expect(run.sha, mainSha);
      expect(run.ref, 'main');
      expect(run.locksProject, isFalse);
      expect(run.version, '1.2.3');
      expect(run.build, 1);
      expect(run.state, RunState.queued);
      expect(run.jobs.map((job) => (job.name, job.stage, job.state)), [
        ('Build dev for android', 0, JobState.queued),
        ('Build dev for ios', 0, JobState.queued),
      ]);
      expect(run.jobs.map((job) => job.capabilities), [
        ['android', 'flutter'],
        ['flutter', 'ios-sign'],
      ]);
      expect(run.workflowVersionId, startsWith('wfv_'));
    });

    test('plans the steps of an Android build', () async {
      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(platforms: ['android']),
      );

      final job = await harness.job(run.jobs.single.id);
      expect(harness.kinds(job), [
        'git.checkout',
        'guard',
        'version.bump',
        'build.android',
        'record.manifest',
      ]);
      final worktree = '/data/worktrees/42/${job.id}';
      final checkout = await harness.input(job, 'git.checkout');
      expect(
        (checkout['worktree'] as Map)['path'],
        worktree,
        reason: 'the worktree is named after the job',
      );
      expect(checkout.containsKey('commitFromJob'), isFalse);
      final bump = await harness.input(job, 'version.bump');
      expect(bump['version'], '1.2.3+1');
      expect((bump['worktree'] as Map)['versionFiles'], [
        'pubspec.yaml',
        'ios/Runner/Info-dev.plist',
      ]);
      final build = await harness.input(job, 'build.android');
      expect(build['flavor'], 'dev');
      expect(build['target'], 'lib/main_dev.dart');
      expect(build['version'], '1.2.3+1');
      expect(build['flutterVersion'], '3.47.6');
      expect(build['artifact'], 'apk');
      expect(build.containsKey('dartDefineFile'), isFalse);
      final guard = await harness.input(job, 'guard');
      expect(guard['checks'], ['source', 'credentials']);
      expect(guard['flavorId'], 'flv_dev');
      expect(guard['androidAppId'], 'ly.demo.dev');
      expect(guard['storeCountry'], 'us');
      final manifest = await harness.input(job, 'record.manifest');
      expect(manifest['flavors'], ['dev']);
    });

    test('plans an iOS build with the export options', () async {
      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(
          platforms: ['ios'],
          inputs: {'dartDefineFile': 'env/dev.json'},
        ),
      );

      final job = await harness.job(run.jobs.single.id);
      expect(harness.kinds(job), contains('build.ios'));
      final build = await harness.input(job, 'build.ios');
      expect(build['exportOptionsPlist'], 'ios/ExportOptions.plist');
      expect(build['dartDefineFile'], 'env/dev.json');
    });

    test(
      'uploads an Android build to Firebase when it has an app id',
      () async {
        await harness.saveCredential('dev', CredentialKind.firebaseSa);

        final run = await harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(
            platforms: ['android'],
            inputs: {
              'firebaseAppIds': {
                'dev': {'android': '1:123456789012:android:abc'},
              },
              'testerGroups': ['qa'],
              'notes': 'Notes.',
            },
          ),
        );

        final job = await harness.job(run.jobs.single.id);
        expect(harness.kinds(job).last, 'upload.firebase');
        final upload = await harness.input(job, 'upload.firebase');
        expect(upload, {
          'artifactName': 'dev-1.2.3+1.apk',
          'appId': '1:123456789012:android:abc',
          'version': '1.2.3+1',
          'serviceAccountSecret': 'credential.dev.firebase_sa',
          'groupAliases': ['qa'],
          'releaseNotes': 'Notes.',
        });
      },
    );

    test('leaves blank release notes out', () async {
      await harness.saveCredential('dev', CredentialKind.firebaseSa);

      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(
          platforms: ['android'],
          inputs: {
            'firebaseAppIds': {
              'dev': {'android': '1:123456789012:android:abc'},
            },
          },
        ),
      );

      final upload = await harness.input(
        await harness.job(run.jobs.single.id),
        'upload.firebase',
      );
      expect(upload.containsKey('releaseNotes'), isFalse);
    });

    test(
      'refuses a Firebase upload when the flavor has no service account',
      () async {
        await expectLater(
          harness.dispatchBuiltin(
            'dev-build',
            const DispatchRequest(
              platforms: ['android'],
              inputs: {
                'firebaseAppIds': {
                  'dev': {'android': '1:123456789012:android:abc'},
                },
              },
            ),
          ),
          _dispatchError(
            allOf(
              contains('The flavor "dev" has no firebase_sa credential saved'),
              startsWith('Line '),
            ),
          ),
        );
        expect(
          harness.counters.counterOf('prj_1', '.'),
          1,
          reason: 'a build number is never handed back (D-11)',
        );
        expect(
          await harness.jobs.jobs.list(states: JobState.values.toSet()),
          isEmpty,
        );
      },
    );

    test(
      'uploads an iOS build to TestFlight with the key of the flavor',
      () async {
        await harness.saveCredential('dev', CredentialKind.ascKey);

        final run = await harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(
            platforms: ['ios'],
            inputs: {
              'appleAppIds': {'dev': '1234567890'},
            },
          ),
        );

        final upload = await harness.input(
          await harness.job(run.jobs.single.id),
          'upload.appStore',
        );
        expect(upload, {
          'artifactName': 'dev-1.2.3+1.ipa',
          'bundleId': 'ly.demo.dev',
          'appleAppId': '1234567890',
          'version': '1.2.3+1',
          'auth': {'type': 'apiKey', 'keySecret': 'credential.dev.asc_key'},
        });
      },
    );

    test(
      'uploads an iOS build with an Apple ID when there is no key',
      () async {
        await harness.saveCredential(
          'dev',
          CredentialKind.appleId,
          account: 'dev@example.com',
        );

        final run = await harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(
            platforms: ['ios'],
            inputs: {
              'appleAppIds': {'dev': '1234567890'},
            },
          ),
        );

        final upload = await harness.input(
          await harness.job(run.jobs.single.id),
          'upload.appStore',
        );
        expect(upload['auth'], {
          'type': 'appleId',
          'appleId': 'dev@example.com',
          'passwordSecret': 'credential.dev.apple_id',
        });
      },
    );

    test('refuses an iOS upload without a key or an Apple ID', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(
            platforms: ['ios'],
            inputs: {
              'appleAppIds': {'dev': '1234567890'},
            },
          ),
        ),
        _dispatchError(contains('no App Store Connect key or Apple ID')),
      );
    });

    test('refuses an Apple ID credential that has no Apple ID', () async {
      await harness.saveCredential('dev', CredentialKind.appleId);

      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(
            platforms: ['ios'],
            inputs: {
              'appleAppIds': {'dev': '1234567890'},
            },
          ),
        ),
        _dispatchError(contains('has no Apple ID')),
      );
    });

    test('passes the keystore of the flavor to an Android build', () async {
      await harness.saveCredential('dev', CredentialKind.keystore);

      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(platforms: ['android']),
      );

      final build = await harness.input(
        await harness.job(run.jobs.single.id),
        'build.android',
      );
      expect(build['secretFiles'], {
        'XPATH_KEYSTORE_FILE': 'credential.dev.keystore',
      });
      expect(build['secretEnvironment'], {
        'XPATH_KEYSTORE_STORE_PASSWORD':
            'credential.dev.keystore.storePassword',
        'XPATH_KEYSTORE_KEY_PASSWORD': 'credential.dev.keystore.keyPassword',
      });
    });

    test('announces the run', () async {
      final run = await harness.dispatchBuiltin('dev-build');

      final events = <EngineEvent>[];
      final subscription = harness.events
          .subscribe(after: 0)
          .listen((e) => events.add(e.event));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(
        events.whereType<RunDispatched>().single,
        RunDispatched(
          runId: run.id,
          projectId: 'prj_1',
          workflowId: await harness.builtin('dev-build'),
          jobIds: run.jobs.map((job) => job.id).toList(),
        ),
      );
    });

    test('says why a queued job waits when no runner can do it', () async {
      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(platforms: ['android']),
      );

      final job = await harness.job(run.jobs.single.id);
      expect(job.state, JobState.queued);
      expect(job.message, 'No runner can do android, flutter.');
    });

    test('keeps the request in the run', () async {
      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(platforms: ['android'], ref: 'main'),
      );

      final stored = (await harness.runs.get(run.id))!;
      expect(stored.request, {
        'ref': 'main',
        'platforms': ['android'],
        'inputs': <String, dynamic>{},
      });
      expect(stored.workflowId, await harness.builtin('dev-build'));
      expect(stored.sha, mainSha);
    });
  });

  group('the prod-release workflow', () {
    test(
      'locks the project and makes the prepare, build and finalize jobs',
      () async {
        final run = await harness.dispatchBuiltin(
          'prod-release',
          const DispatchRequest(bump: VersionBump.patch),
        );

        expect(run.locksProject, isTrue);
        expect(run.version, '1.2.4');
        expect(run.build, 1);
        expect(run.jobs.map((job) => (job.name, job.stage)), [
          ('Prepare prod', 0),
          ('Build prod for android', 1),
          ('Build prod for ios', 1),
          ('Tag prod', 2),
        ]);
      },
    );

    test(
      'gates the release before the branch and the push before it leaves',
      () async {
        final run = await harness.dispatchBuiltin(
          'prod-release',
          const DispatchRequest(version: '2.0.0'),
        );

        final jobs = await harness.jobsOf(run);
        final prepare = jobs.first;
        expect(harness.kinds(prepare), [
          'git.checkout',
          'guard',
          'version.bump',
          'guard',
          'guard',
          'gate',
          'git.releaseBranch',
        ]);
        expect(await harness.input(prepare, 'gate'), {
          'action': 'prod_release',
          'projectId': 'prj_1',
          'sha': mainSha,
          'version': '2.0.0+1',
        });
        final tag = jobs.last;
        expect(harness.kinds(tag), [
          'git.checkout',
          'git.tag',
          'gate',
          'git.push',
          'github.createPr',
        ]);
        expect((await harness.input(tag, 'gate'))['action'], 'push');
        expect(await harness.input(tag, 'git.tag'), {
          'worktree': isA<Map<String, dynamic>>(),
          'name': 'v2.0.0+1',
          'message': 'Release 2.0.0+1',
        });
        final push = await harness.input(tag, 'git.push');
        expect(push['branch'], 'release/2.0.0');
        expect(push['tag'], 'v2.0.0+1');
      },
    );

    test(
      'has every later job start from the version commit of the prepare job',
      () async {
        final run = await harness.dispatchBuiltin('prod-release');

        final jobs = await harness.jobsOf(run);
        final prepare = jobs.first.id;
        for (final job in jobs.skip(1)) {
          final checkout = await harness.input(job, 'git.checkout');
          expect(checkout['commitFromJob'], prepare, reason: job.name);
        }
      },
    );

    test('builds a Shorebird flavor with shorebird release', () async {
      await harness.saveCredential('prod', CredentialKind.shorebird);
      await harness.saveCredential('prod', CredentialKind.playSa);
      await harness.saveCredential('prod', CredentialKind.ascKey);
      await harness.saveCredential('prod', CredentialKind.firebaseSa);

      final run = await harness.dispatchBuiltin(
        'prod-release',
        const DispatchRequest(
          inputs: {
            'firebaseAppIds': {
              'prod': {'android': '1:123456789012:android:abc'},
            },
            'appleAppIds': {'prod': '1234567890'},
            'playTrack': 'beta',
            'notes': 'Hello.',
          },
        ),
      );

      final jobs = await harness.jobsOf(run);
      final android = jobs.firstWhere(
        (job) => job.name == 'Build prod for android',
      );
      expect(harness.kinds(android), [
        'git.checkout',
        'guard',
        'guard',
        'shorebird.release',
        'symbols.archive',
        'record.manifest',
        'upload.play',
        'upload.firebase',
      ]);
      final release = await harness.input(android, 'shorebird.release');
      expect(release['platform'], 'android');
      expect(release['shorebirdAppId'], 'sb-prod');
      expect(release['artifact'], 'apk');
      expect(release['obfuscate'], isTrue);
      expect(release['tokenSecret'], 'credential.prod.shorebird');
      expect(release['version'], '1.2.3+1');
      final play = await harness.input(android, 'upload.play');
      expect(play['artifactName'], 'prod-1.2.3+1.aab');
      expect(play['packageName'], 'ly.demo');
      expect(play['track'], 'beta');
      expect(play['releaseNotes'], {'en-US': 'Hello.'});
      expect(play['serviceAccountSecret'], 'credential.prod.play_sa');
      final symbols = await harness.input(android, 'symbols.archive');
      expect(symbols['android'], isTrue);
      expect(symbols['ios'], isFalse);

      final ios = jobs.firstWhere((job) => job.name == 'Build prod for ios');
      expect(harness.kinds(ios), [
        'git.checkout',
        'guard',
        'guard',
        'shorebird.release',
        'symbols.archive',
        'record.manifest',
        'upload.appStore',
      ]);
      expect(
        (await harness.input(ios, 'shorebird.release'))['platform'],
        'ios',
      );
      expect((await harness.input(ios, 'guard', nth: 1))['checks'], [
        'appStoreTrain',
      ]);
      expect((await harness.input(android, 'guard', nth: 1))['checks'], [
        'playTargetSdk',
      ]);
    });

    test('builds a flavor without Shorebird with flutter build', () async {
      final app = AppProfile(
        name: 'demo',
        path: '.',
        version: '1.2.3+45',
        hasAndroid: true,
        hasIos: true,
        flutterVersion: '3.47.6',
        flavors: [
          demoApp.flavors.first,
          demoApp.flavors.last.copyWith(shorebird: false),
        ],
      );
      harness = await DispatchHarness.create(apps: [app]);

      final run = await harness.dispatchBuiltin('prod-release');

      final jobs = await harness.jobsOf(run);
      final android = jobs.firstWhere(
        (job) => job.name == 'Build prod for android',
      );
      expect(harness.kinds(android), contains('build.android'));
      expect(
        (await harness.input(android, 'build.android'))['artifact'],
        'aab',
      );
      final ios = jobs.firstWhere((job) => job.name == 'Build prod for ios');
      expect(harness.kinds(ios), contains('build.ios'));
    });

    test('waits behind a release of the same project', () async {
      final first = await harness.dispatchBuiltin('prod-release');
      final second = await harness.dispatchBuiltin('prod-release');

      expect(first.id, isNot(second.id));
      expect(second.build, 2, reason: 'each dispatch allocates a number');
    });
  });

  group('the shorebird-patch workflow', () {
    test('needs the release it patches', () async {
      await expectLater(
        harness.dispatchBuiltin('shorebird-patch'),
        _dispatchError(
          'This workflow patches a release: give '
          '"releaseVersion", for example 5.4.1+3283.',
        ),
      );
    });

    test('patches the shorebird flavors of the release', () async {
      harness.git.tags.addAll({
        'v1.2.0+30': 'c1',
        'v1.2.0+30-p1': 'c2',
        'v1.2.0+30-p2': 'c3',
        'v1.2.0+31-p7': 'c4',
        'v1.1.0+30-p9': 'c5',
        'not-a-release': 'c6',
      });

      final run = await harness.dispatchBuiltin(
        'shorebird-patch',
        const DispatchRequest(releaseVersion: '1.2.0+30'),
      );

      expect(run.locksProject, isTrue);
      expect(run.version, isNull);
      expect(run.build, isNull);
      expect(run.jobs.map((job) => (job.name, job.stage)), [
        ('Patch prod for android', 0),
        ('Patch prod for ios', 0),
        ('Tag the patch of prod', 1),
      ]);
      final jobs = await harness.jobsOf(run);
      final android = jobs.first;
      expect(harness.kinds(android), [
        'git.checkout',
        'guard',
        'gate',
        'shorebird.patch',
      ]);
      expect(await harness.input(android, 'gate'), {
        'action': 'prod_patch',
        'projectId': 'prj_1',
        'sha': mainSha,
        'version': '1.2.0+30-p3',
      });
      final guard = await harness.input(android, 'guard');
      expect(guard['releaseVersion'], '1.2.0+30');
      expect(guard['checks'], [
        'source',
        'patchTarget',
        'patchNativeDiff',
        'credentials',
      ]);
      expect(guard['shorebirdAppId'], 'sb-prod');
      final patch = await harness.input(android, 'shorebird.patch');
      expect(patch['version'], '1.2.0+30');
      expect(patch['platform'], 'android');
      expect(patch['allowNativeDiffs'], isFalse);
      final tagJob = jobs.last;
      expect((await harness.input(tagJob, 'git.tag'))['name'], 'v1.2.0+30-p3');
      expect(
        (await harness.input(tagJob, 'git.tag'))['message'],
        'Patch 3 of 1.2.0+30',
      );
      final push = await harness.input(tagJob, 'git.push');
      expect(push.containsKey('branch'), isFalse);
      expect(push['tag'], 'v1.2.0+30-p3');
      expect(
        (await harness.input(
          tagJob,
          'git.checkout',
        )).containsKey('commitFromJob'),
        isFalse,
      );
    });

    test('starts at patch 1', () async {
      final run = await harness.dispatchBuiltin(
        'shorebird-patch',
        const DispatchRequest(
          releaseVersion: '1.2.0+30',
          platforms: ['android'],
          inputs: {'allowNativeDiffs': true},
        ),
      );

      final jobs = await harness.jobsOf(run);
      expect(
        (await harness.input(jobs.last, 'git.tag'))['name'],
        'v1.2.0+30-p1',
      );
      expect(
        (await harness.input(
          jobs.first,
          'shorebird.patch',
        ))['allowNativeDiffs'],
        isTrue,
      );
    });

    test('has nothing to run when no flavor has Shorebird', () async {
      final app = AppProfile(
        name: 'demo',
        path: '.',
        version: '1.2.3+45',
        hasAndroid: true,
        flavors: [
          demoApp.flavors.first,
          demoApp.flavors.last.copyWith(shorebird: false),
        ],
      );
      harness = await DispatchHarness.create(apps: [app]);

      await expectLater(
        harness.dispatchBuiltin(
          'shorebird-patch',
          const DispatchRequest(releaseVersion: '1.2.0+30'),
        ),
        _dispatchError(startsWith('Nothing to run')),
      );
    });

    test('refuses a release version that is not exact', () async {
      for (final bad in ['latest', '1.2.0', '1.2']) {
        await expectLater(
          harness.dispatchBuiltin(
            'shorebird-patch',
            DispatchRequest(releaseVersion: bad),
          ),
          throwsA(isA<DispatchException>()),
          reason: bad,
        );
      }
    });
  });

  group('the test workflow', () {
    test('runs the tests and the analyzer in one job', () async {
      final run = await harness.dispatchBuiltin(
        'test',
        const DispatchRequest(
          ref: 'main',
          inputs: {
            'paths': ['test/a_test.dart'],
            'tags': ['fast'],
          },
        ),
      );

      expect(run.build, isNull, reason: 'a test run allocates no build number');
      expect(harness.counters.counterOf('prj_1', '.'), 0);
      expect(run.jobs.single.name, 'Test demo');
      expect(run.jobs.single.capabilities, ['flutter']);
      final job = await harness.job(run.jobs.single.id);
      expect(harness.kinds(job), ['git.checkout', 'test', 'analyze']);
      final test = await harness.input(job, 'test');
      expect(test['branch'], 'main');
      expect(test['baseBranch'], 'main');
      expect(test['flutterVersion'], '3.47.6');
      expect(test['paths'], ['test/a_test.dart']);
      expect(test['tags'], ['fast']);
      expect(
        harness.git.calls.where((c) => c.startsWith('createWorktree')),
        isEmpty,
        reason: 'it needs no version, so it reads none',
      );
    });
  });

  group('the request', () {
    test('resolves the ref and fetches first', () async {
      harness.git.refs['release/1.2'] = 'b' * 40;

      final run = await harness.dispatchBuiltin(
        'test',
        const DispatchRequest(ref: 'release/1.2'),
      );

      expect(run.sha, 'b' * 40);
      expect(run.ref, 'release/1.2');
      expect(harness.git.calls.take(3), [
        'ensureMirror 42 https://github.com/octo/demo.git',
        'fetch',
        'resolveRef release/1.2',
      ]);
    });

    test('says when the ref is not there', () async {
      await expectLater(
        harness.dispatchBuiltin('test', const DispatchRequest(ref: 'nope')),
        _dispatchError('Cannot find nope.'),
      );
    });

    test('lets the mirror failure through', () async {
      harness.git.fetchFailure = const GitException('network is down');

      await expectLater(
        harness.dispatchBuiltin('test'),
        throwsA(isA<GitException>()),
      );
    });

    test('bumps the version the way it is asked', () async {
      for (final (request, expected) in <(DispatchRequest, String)>[
        (const DispatchRequest(bump: VersionBump.major), '2.0.0'),
        (const DispatchRequest(bump: VersionBump.minor), '1.3.0'),
        (const DispatchRequest(bump: VersionBump.patch), '1.2.4'),
        (const DispatchRequest(bump: VersionBump.keep), '1.2.3'),
        (const DispatchRequest(), '1.2.3'),
        (
          const DispatchRequest(version: '3.1.4', bump: VersionBump.major),
          '3.1.4',
        ),
      ]) {
        final run = await harness.dispatchBuiltin('dev-build', request);
        expect(run.version, expected, reason: '$request');
      }
    });

    test(
      'allocates one build number per run, after the tags and the stores',
      () async {
        harness.git.tags['v1.2.3+7'] = 'c1';
        harness.stores.builds = const StoreBuilds({20, 30});

        final first = await harness.dispatchBuiltin('dev-build');
        final second = await harness.dispatchBuiltin('dev-build');

        expect(first.build, 31);
        expect(second.build, 32);
        expect(harness.counters.counterOf('prj_1', '.'), 32);
      },
    );

    test('refuses a version that is not x.y.z', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(version: '1.2'),
        ),
        _dispatchError(contains('1.2')),
      );
    });

    test('says when the app has no readable version', () async {
      harness.pubspec.files['pubspec.yaml'] = 'name: demo\n';

      await expectLater(
        harness.dispatchBuiltin('dev-build'),
        _dispatchError(startsWith('pubspec.yaml: ')),
      );
      expect(
        harness.git.calls.last,
        startsWith('removeWorktree'),
        reason: 'the worktree that read the version is gone',
      );
    });

    test('knows the flavors by name', () async {
      final run = await harness.dispatchBuiltin(
        'dev-build',
        const DispatchRequest(flavors: ['prod'], platforms: ['android']),
      );

      expect(run.jobs.single.name, 'Build prod for android');
      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(flavors: ['qa']),
        ),
        _dispatchError('The app has no flavor "qa" (it has dev, prod).'),
      );
    });

    test('takes the only flavor of an app whatever it is called', () async {
      const app = AppProfile(
        name: 'demo',
        path: '.',
        hasAndroid: true,
        version: '1.0.0+1',
        flavors: [
          FlavorProfile(
            name: 'default',
            entrypoint: 'lib/main.dart',
            implicit: true,
          ),
        ],
      );
      harness = await DispatchHarness.create(apps: [app]);

      final run = await harness.dispatchBuiltin('prod-release');

      expect(run.jobs.first.name, 'Prepare default');
      final build = await harness.input(
        await harness.job(run.jobs[1].id),
        'build.android',
      );
      expect(build.containsKey('flavor'), isFalse);
      expect(build.containsKey('target'), isFalse);
      final upload = await harness.job(run.jobs[1].id);
      expect(harness.kinds(upload), contains('build.android'));
    });

    test(
      'needs a production flavor for a release, and a dev one for a dev build',
      () async {
        final prodOnly = AppProfile(
          name: 'demo',
          path: '.',
          hasAndroid: true,
          version: '1.0.0+1',
          flavors: [
            demoApp.flavors.last,
            demoApp.flavors.last.copyWith(prod: true),
          ].map((f) => f).toList(),
        );
        final devOnly = AppProfile(
          name: 'demo',
          path: '.',
          hasAndroid: true,
          version: '1.0.0+1',
          flavors: [
            demoApp.flavors.first,
            const FlavorProfile(name: 'qa', entrypoint: 'lib/main_qa.dart'),
          ],
        );

        harness = await DispatchHarness.create(apps: [prodOnly]);
        await expectLater(
          harness.dispatchBuiltin('dev-build'),
          _dispatchError(
            startsWith('Every flavor of the app is a production flavor'),
          ),
        );
        harness = await DispatchHarness.create(apps: [devOnly]);
        await expectLater(
          harness.dispatchBuiltin('prod-release'),
          _dispatchError(
            startsWith('No flavor of the app is a production flavor'),
          ),
        );
      },
    );

    test('knows the platforms the app has', () async {
      final androidOnly = AppProfile(
        name: 'demo',
        path: '.',
        hasAndroid: true,
        version: '1.0.0+1',
        flavors: demoApp.flavors,
      );
      harness = await DispatchHarness.create(apps: [androidOnly]);

      final run = await harness.dispatchBuiltin('dev-build');
      expect(run.jobs.map((job) => job.name), ['Build dev for android']);
      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(platforms: ['ios']),
        ),
        _dispatchError('The app has no iOS project.'),
      );
      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(platforms: ['windows']),
        ),
        _dispatchError('Unknown platform "windows"; use android or ios.'),
      );
      harness = await DispatchHarness.create(
        apps: [
          AppProfile(
            name: 'demo',
            path: '.',
            hasIos: true,
            version: '1.0.0+1',
            flavors: demoApp.flavors,
          ),
        ],
      );
      await expectLater(
        harness.dispatchBuiltin(
          'dev-build',
          const DispatchRequest(platforms: ['android']),
        ),
        _dispatchError('The app has no Android project.'),
      );
    });

    test('has nothing to run for an app with no platform', () async {
      harness = await DispatchHarness.create(
        apps: [
          AppProfile(
            name: 'demo',
            path: '.',
            version: '1.0.0+1',
            flavors: demoApp.flavors,
          ),
        ],
      );

      await expectLater(
        harness.dispatchBuiltin('dev-build'),
        _dispatchError(
          'Nothing to run: no job is left for the flavors (dev) and the '
          'platforms () of this dispatch.',
        ),
      );
    });

    test('needs to know the app when there are several', () async {
      final second = AppProfile(
        name: 'second',
        path: 'apps/second',
        hasAndroid: true,
        version: '1.0.0+1',
        flavors: demoApp.flavors,
      );
      harness = await DispatchHarness.create(apps: [demoApp, second]);

      await expectLater(
        harness.dispatchBuiltin('test'),
        _dispatchError(
          'The project has several apps: give "app" (one of ., apps/second).',
        ),
      );
      await expectLater(
        harness.dispatchBuiltin(
          'test',
          const DispatchRequest(app: 'apps/none'),
        ),
        _dispatchError(
          'The project has no app at "apps/none" (it has ., apps/second).',
        ),
      );
      harness.pubspec.files['apps/second/pubspec.yaml'] = 'version: 3.0.0+3\n';
    });

    test('says when the project has no app', () async {
      harness = await DispatchHarness.create(apps: const []);

      await expectLater(
        harness.dispatchBuiltin('test'),
        _dispatchError('The project has no Flutter app; scan it again.'),
      );
    });

    test('knows the inputs the workflow declares', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'test',
          const DispatchRequest(inputs: {'nope': 1}),
        ),
        _dispatchError(
          'The workflow has no input "nope" (it has paths, tags).',
        ),
      );
    });

    test('says when a workflow without inputs gets one', () async {
      await expectLater(
        harness.dispatchCustom('''
schema: 1
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: git.checkout
''', const DispatchRequest(inputs: {'x': 1})),
        _dispatchError('The workflow has no input "x".'),
      );
    });

    test('needs the inputs that are required', () async {
      await expectLater(
        harness.dispatchCustom('''
schema: 1
inputs:
  notes:
    required: true
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: git.checkout
'''),
        _dispatchError('The input "notes" is needed.'),
      );
    });

    test('refuses a workflow that no longer is valid', () async {
      final id = await harness.custom('''
schema: 1
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: git.checkout
''');
      // A later engine drops a step type that a stored workflow still uses.
      await harness.workflowRepository.addVersion(
        workflowId: id,
        versionId: 'wfv_stale',
        yaml: '''
schema: 1
stages:
  - name: a
    jobs:
      j:
        steps:
          - kind: retired.step
''',
        createdAt: DateTime.utc(2026),
      );

      await expectLater(
        harness.dispatcher.dispatch('prj_1', id, const DispatchRequest()),
        throwsA(isA<WorkflowInvalidException>()),
      );
    });

    test('says when the workflow is not there', () async {
      await expectLater(
        harness.dispatcher.dispatch(
          'prj_1',
          'wf_nope',
          const DispatchRequest(),
        ),
        throwsA(isA<WorkflowNotFoundException>()),
      );
    });
  });
}
