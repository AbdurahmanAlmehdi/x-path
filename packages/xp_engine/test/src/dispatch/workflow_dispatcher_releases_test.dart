import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/dispatch_harness.dart';

Matcher _dispatchError(Object message) => throwsA(
  isA<DispatchException>().having((e) => e.message, 'message', message),
);

/// A workflow of one job with [steps] (YAML lines indented to ten spaces).
String _workflow(String steps) =>
    '''
schema: 1
stages:
  - name: only
    jobs:
      job:
        steps:
$steps
''';

void main() {
  late FakeReleaseOpener releases;
  late DispatchHarness harness;

  setUp(() async {
    releases = FakeReleaseOpener();
    harness = await DispatchHarness.create(releases: releases);
  });

  Future<String?> releaseOf(String jobId) async =>
      (await harness.jobs.jobs.get(jobId))!.releaseId;

  group('a production release', () {
    test('makes a release of the flavor and links every job to it', () async {
      await harness.saveCredential('prod', CredentialKind.playSa);
      await harness.saveCredential('prod', CredentialKind.ascKey);

      final run = await harness.dispatchBuiltin(
        'prod-release',
        const DispatchRequest(
          inputs: {
            'appleAppIds': {'prod': '1234567890'},
          },
        ),
      );

      final opening = releases.openings.single;
      expect(opening.projectId, 'prj_1');
      expect(opening.appPath, '.');
      expect(opening.runId, run.id);
      expect(opening.version, '1.2.3');
      expect(opening.build, 1);
      expect(opening.baseBranch, 'main');
      expect(opening.storeCountry, 'us');
      expect(opening.flavors.map((f) => f.flavor), ['prod']);
      final kinds = opening.flavors.single.steps.map((step) => step.kind);
      expect(kinds, containsAll(['upload.play', 'upload.appStore', 'git.tag']));
      for (final job in run.jobs) {
        expect(await releaseOf(job.id), 'rel_prod', reason: job.name);
      }
    });

    test('makes one release per flavor', () async {
      final run = await harness.dispatchBuiltin(
        'prod-release',
        const DispatchRequest(flavors: ['dev', 'prod']),
      );

      expect(releases.openings.single.flavors.map((f) => f.flavor), [
        'dev',
        'prod',
      ]);
      final prepare = run.jobs.first;
      expect(await releaseOf(prepare.id), 'rel_dev');
      expect(await releaseOf(run.jobs.last.id), 'rel_prod');
    });

    test(
      'opens the pull request of the release branch after the push',
      () async {
        final run = await harness.dispatchBuiltin(
          'prod-release',
          const DispatchRequest(version: '2.0.0'),
        );

        final tag = (await harness.jobsOf(run)).last;
        final pr = await harness.input(tag, 'github.createPr');
        expect(pr, {
          'githubRepoId': 42,
          'head': 'release/2.0.0',
          'base': 'main',
          'title': 'Release 2.0.0 (prod)',
          'body': contains('release branch of 2.0.0'),
        });
      },
    );

    test('is not a release without an opener', () async {
      harness = await DispatchHarness.create();

      final run = await harness.dispatchBuiltin('prod-release');

      for (final job in run.jobs) {
        expect(await releaseOf(job.id), isNull);
      }
    });

    test('a dev build makes no release', () async {
      final run = await harness.dispatchBuiltin('dev-build');

      expect(releases.openings, isEmpty);
      expect(await releaseOf(run.jobs.first.id), isNull);
    });

    test('a workflow without a flavor in its matrix makes none', () async {
      final run = await harness.dispatchCustom(
        _workflow('''
          - kind: version.bump
          - kind: git.releaseBranch
'''),
      );

      expect(releases.openings.single.flavors, isEmpty);
      expect(await releaseOf(run.jobs.single.id), isNull);
    });
  });

  group('a new build of a release', () {
    test(
      'attaches the run, and skips the check that the version shipped',
      () async {
        final run = await harness.dispatchBuiltin(
          'prod-release',
          const DispatchRequest(
            ref: 'main',
            version: '1.2.3',
            release: 'rel_1',
          ),
        );

        expect(releases.attached, ['rel_1 prj_1 build ${run.id} 1']);
        expect(releases.openings, isEmpty);
        final jobs = await harness.jobsOf(run);
        expect(harness.kinds(jobs.first), [
          'git.checkout',
          'guard',
          'version.bump',
          'guard',
          'gate',
          'git.releaseBranch',
          'gate',
          'git.push',
        ]);
        for (final job in run.jobs) {
          expect(await releaseOf(job.id), 'rel_1', reason: job.name);
        }
        expect((await harness.input(jobs.first, 'gate'))['version'], '1.2.3+1');
      },
    );

    test('shows the workflow the release as `release`', () async {
      final run = await harness.dispatchCustom(
        _workflow('''
          - kind: version.bump
          - kind: guard
            if: release == 'rel_1'
            with:
              checks: [versionSync]
          - kind: guard
            if: "!release"
            with:
              checks: [newReleaseNumber]
'''),
        const DispatchRequest(release: 'rel_1', version: '1.2.3'),
      );

      final job = await harness.job(run.jobs.single.id);
      expect(harness.kinds(job), ['version.bump', 'guard']);
      expect((await harness.input(job, 'guard'))['checks'], ['versionSync']);
    });

    test('says why the release cannot take it', () async {
      releases.attachFailure = const ReleaseStateException(
        'Only a rejected release gets a new build.',
      );

      await expectLater(
        harness.dispatchBuiltin(
          'prod-release',
          const DispatchRequest(release: 'rel_1', version: '1.2.3'),
        ),
        _dispatchError('Only a rejected release gets a new build.'),
      );
      expect(
        await harness.jobs.jobs.list(states: {JobState.queued}),
        isEmpty,
        reason: 'nothing is stored',
      );
    });
  });

  group('the merge of a release', () {
    test(
      'attaches the run and gates the merge on the released commit',
      () async {
        final run = await harness.dispatchBuiltin(
          'release-merge',
          const DispatchRequest(
            ref: 'main',
            flavors: ['prod'],
            releaseVersion: '1.2.0+5',
            release: 'rel_1',
          ),
        );

        expect(releases.attached, ['rel_1 prj_1 merge ${run.id} null']);
        expect(run.locksProject, isFalse);
        expect(run.build, isNull);
        final job = await harness.job(run.jobs.single.id);
        expect(harness.kinds(job), ['gate', 'github.mergePr']);
        expect(await harness.input(job, 'gate'), {
          'action': 'merge',
          'projectId': 'prj_1',
          'sha': mainSha,
          'version': '1.2.0+5',
        });
        expect(await harness.input(job, 'github.mergePr'), {
          'releaseId': 'rel_1',
          'githubRepoId': 42,
        });
        expect(await releaseOf(job.id), 'rel_1');
      },
    );

    test('needs a release to merge', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'release-merge',
          const DispatchRequest(flavors: ['prod']),
        ),
        throwsA(
          isA<DispatchException>().having(
            (e) => e.message,
            'message',
            contains('There is no release to merge'),
          ),
        ),
      );
    });
  });

  group('the rollout of a release', () {
    test('attaches the run and gates the change on the release', () async {
      final run = await harness.dispatchBuiltin(
        'release-rollout',
        const DispatchRequest(
          ref: 'main',
          flavors: ['prod'],
          releaseVersion: '1.2.0+5',
          release: 'rel_1',
          inputs: {'store': 'play', 'action': 'fraction', 'userFraction': 0.2},
        ),
      );

      expect(releases.attached, ['rel_1 prj_1 rollout ${run.id} null']);
      expect(run.locksProject, isFalse);
      final job = await harness.job(run.jobs.single.id);
      expect(harness.kinds(job), ['gate', 'store.rollout']);
      expect(await harness.input(job, 'gate'), {
        'action': 'rollout',
        'projectId': 'prj_1',
        'sha': mainSha,
        'version': '1.2.0+5',
      });
      expect(await harness.input(job, 'store.rollout'), {
        'releaseId': 'rel_1',
        'store': 'play',
        'action': 'fraction',
        'userFraction': 0.2,
      });
    });

    test('says what is wrong with the change', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'release-rollout',
          const DispatchRequest(
            ref: 'main',
            flavors: ['prod'],
            release: 'rel_1',
            inputs: {'store': 'apple', 'action': 'fraction'},
          ),
        ),
        throwsA(isA<DispatchException>()),
      );
    });

    test('needs a release to roll out', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'release-rollout',
          const DispatchRequest(
            flavors: ['prod'],
            inputs: {'store': 'apple', 'action': 'pause'},
          ),
        ),
        throwsA(
          isA<DispatchException>().having(
            (e) => e.message,
            'message',
            contains('There is no release to roll out'),
          ),
        ),
      );
    });
  });

  group('a Shorebird patch', () {
    test('links each job to the release of its flavor', () async {
      releases.patchables['prod'] = 'rel_prod';

      final run = await harness.dispatchBuiltin(
        'shorebird-patch',
        const DispatchRequest(
          releaseVersion: '1.2.0+30',
          platforms: ['android'],
        ),
      );

      expect(releases.attached, ['rel_prod prj_1 patch ${run.id} null']);
      for (final job in run.jobs) {
        expect(await releaseOf(job.id), 'rel_prod');
      }
    });

    test('of a release the engine does not track links none', () async {
      final run = await harness.dispatchBuiltin(
        'shorebird-patch',
        const DispatchRequest(
          releaseVersion: '1.2.0+30',
          platforms: ['android'],
        ),
      );

      expect(releases.attached, isEmpty);
      expect(await releaseOf(run.jobs.first.id), isNull);
    });

    test('is promoted behind the prod_patch gate', () async {
      final run = await harness.dispatchBuiltin(
        'shorebird-track',
        const DispatchRequest(
          ref: 'main',
          flavors: ['prod'],
          releaseVersion: '1.2.0+30',
          release: 'rel_1',
          inputs: {'patchNumber': 2, 'action': 'promote'},
        ),
      );

      expect(releases.attached, ['rel_1 prj_1 patch ${run.id} null']);
      expect(run.locksProject, isFalse);
      final job = await harness.job(run.jobs.single.id);
      expect(harness.kinds(job), ['gate', 'shorebird.track']);
      expect((await harness.input(job, 'gate'))['action'], 'prod_patch');
      final track = await harness.input(job, 'shorebird.track');
      expect(track['shorebirdAppId'], 'sb-prod');
      expect(track['releaseVersion'], '1.2.0+30');
      expect(track['patchNumber'], 2);
      expect(track['action'], 'promote');
      expect(RemoteStepPolicy.canRunRemotely(harness.kinds(job)), isFalse);
    });

    test('needs the Shorebird app of the flavor', () async {
      await expectLater(
        harness.dispatchCustom(
          _workflow('''
          - kind: shorebird.track
            with:
              patchNumber: 1
              action: promote
'''),
          const DispatchRequest(releaseVersion: '1.2.0+30', release: 'rel_1'),
        ),
        throwsA(
          isA<DispatchException>().having(
            (e) => e.message,
            'message',
            contains('no Shorebird app id'),
          ),
        ),
      );
    });

    test('needs a patch number and the release it belongs to', () async {
      for (final (request, message) in [
        (
          const DispatchRequest(
            flavors: ['prod'],
            releaseVersion: '1.2.0+30',
            release: 'rel_1',
            inputs: {'action': 'promote'},
          ),
          'Give "patchNumber"',
        ),
        (
          const DispatchRequest(
            flavors: ['prod'],
            release: 'rel_1',
            inputs: {'patchNumber': 2, 'action': 'promote'},
          ),
          'moves a patch of a release',
        ),
      ]) {
        await expectLater(
          harness.dispatchBuiltin('shorebird-track', request),
          throwsA(
            isA<DispatchException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      }
    });
  });

  group('a release that cannot be named', () {
    test('is refused by an engine that tracks no releases', () async {
      harness = await DispatchHarness.create();

      await expectLater(
        harness.dispatchBuiltin(
          'prod-release',
          const DispatchRequest(release: 'rel_1', version: '1.2.3'),
        ),
        _dispatchError('This engine does not track releases.'),
      );
    });

    test('is refused by a workflow that neither builds nor merges', () async {
      await expectLater(
        harness.dispatchBuiltin(
          'test',
          const DispatchRequest(release: 'rel_1'),
        ),
        _dispatchError(
          'A run of a release has to build it again (a "version.bump" step), '
          'merge its pull request (a "github.mergePr" step), change its '
          'rollout (a "store.rollout" step) or move a patch (a '
          '"shorebird.track" step).',
        ),
      );
    });
  });

  group('github.createPr', () {
    test('needs a version', () async {
      await expectLater(
        harness.dispatchCustom(_workflow('          - kind: github.createPr')),
        throwsA(
          isA<DispatchException>().having(
            (e) => e.message,
            'message',
            contains('There is no release version'),
          ),
        ),
      );
    });

    test('takes the title and the body of the workflow', () async {
      final run = await harness.dispatchCustom(
        _workflow('''
          - kind: version.bump
          - kind: github.createPr
            with:
              title: Ship it
              body: Please.
'''),
        const DispatchRequest(version: '3.0.0'),
      );

      final job = await harness.job(run.jobs.single.id);
      final pr = await harness.input(job, 'github.createPr');
      expect(pr['title'], 'Ship it');
      expect(pr['body'], 'Please.');
      expect(pr['head'], 'release/3.0.0');
    });

    test(
      'titles the pull request without a flavor when there is none',
      () async {
        final run = await harness.dispatchCustom(
          _workflow('''
          - kind: version.bump
          - kind: github.createPr
'''),
          const DispatchRequest(version: '3.0.0'),
        );

        final job = await harness.job(run.jobs.single.id);
        expect(
          (await harness.input(job, 'github.createPr'))['title'],
          'Release 3.0.0',
        );
      },
    );
  });
}
