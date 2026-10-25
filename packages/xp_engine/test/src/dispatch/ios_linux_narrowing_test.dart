import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/dispatch_harness.dart';
import '../../helpers/workflow_fixtures.dart';

/// A workflow with one iOS build job: a version, [steps] (YAML lines indented
/// to ten spaces), then `build.ios`.
String _workflow(String steps, {bool flavors = false}) =>
    '''
schema: 1
stages:
  - name: only
    jobs:
      job:
${flavors ? r'''
        matrix:
          flavor: ${{ flavors }}
''' : ''}
        steps:
          - kind: version.bump
$steps
          - kind: build.ios
            with:
              exportOptionsPlist: ios/Export.plist
''';

/// The one flavor of an app without flavors.
const _main = FlavorProfile(
  name: 'main',
  implicit: true,
  entrypoint: 'lib/main.dart',
  iosBundleId: 'ly.demo',
);

/// The demo app without flavors.
const _plain = AppProfile(
  name: 'demo',
  path: '.',
  version: '1.2.3+45',
  flutterVersion: '3.47.6',
  hasIos: true,
  flavors: [_main],
);

/// A Mac that is paired and offline.
class _AwayMac implements PairedRunners {
  @override
  Future<List<PairedRunner>> pairedRunners() async => const [
    PairedRunner(
      id: 'rnr_mac',
      name: 'mac',
      capabilities: {Capability.flutter, Capability.iosSign},
      connected: false,
    ),
  ];
}

void main() {
  /// A harness whose flavor `main` can sign on Linux unless not [signing]:
  /// it has an Apple Distribution identity and an App Store Connect key.
  Future<DispatchHarness> harness({
    AppProfile app = _plain,
    bool linux = true,
    bool mac = true,
    bool signing = true,
  }) async {
    final created = await DispatchHarness.create(
      apps: [app],
      linuxIosBuilds: linux,
    );
    if (mac) created.scheduler.pairedRunners = _AwayMac();
    const main = CredentialFlavor(
      id: 'flv_main',
      projectId: 'prj_1',
      appPath: '.',
      name: 'main',
      iosBundleId: 'ly.demo',
    );
    created.credentials.flavors.add(main);
    if (signing) {
      for (final kind in [
        CredentialKind.appleDistribution,
        CredentialKind.ascKey,
      ]) {
        await created.credentials.put(demoCredential(main, kind));
      }
    }
    return created;
  }

  Future<JobRecord> only(DispatchHarness h, Run run) async =>
      (await h.jobs.jobs.get(run.jobs.single.id))!;

  test('an iOS build needs a Mac or a Linux runner when nothing rules Linux '
      'out', () async {
    final h = await harness(mac: false);

    final run = await h.dispatchCustom(_workflow('', flavors: true));

    final job = await only(h, run);
    expect(job.capabilities, ['flutter', 'ios-sign|ios-linux']);
    expect(job.narrowing, isEmpty);
  });

  test('the build is planned with the identity and the profile the engine '
      'makes, never the ASC key', () async {
    final h = await harness(mac: false);

    final run = await h.dispatchCustom(_workflow('', flavors: true));

    final build = (await h.jobs.jobs.steps(run.jobs.single.id)).last;
    expect(build.input['linuxSigning'], {
      'ASC_SIGNING_KEY': 'credential.main.apple_distribution',
      'ASC_SIGNING_CERT': 'credential.main.apple_distribution.certificate',
      'ASC_PROFILE': 'credential.main.apple_distribution.profile:ly.demo',
    });
  });

  test('a flavor without an identity and a key narrows to ios-sign, with '
      'the reason', () async {
    final h = await harness(signing: false);

    final run = await h.dispatchCustom(_workflow('', flavors: true));

    final job = await only(h, run);
    expect(job.capabilities, ['flutter', 'ios-sign']);
    expect(job.narrowing, [
      contains('the flavor has no Apple Distribution identity'),
    ]);
  });

  test('the dry run shows why a job needs a Mac, from the job and the '
      'scan', () async {
    final h = await harness(
      app: const AppProfile(
        name: 'demo',
        path: '.',
        version: '1.2.3+45',
        flutterVersion: '3.47.6',
        hasIos: true,
        flavors: [_main],
        iosLinuxLimits: ['the app builds its iOS plugins with CocoaPods'],
      ),
    );

    final plan = await h.dispatcher.plan(
      'prj_1',
      await h.custom(_workflow('', flavors: true)),
      const DispatchRequest(),
    );

    final job = plan.stages.single.jobs.single;
    expect(job.capabilities, ['flutter', 'ios-sign']);
    expect(job.narrowing, ['the app builds its iOS plugins with CocoaPods']);
  });

  test('the strip step narrows the job to ios-sign, once, with the '
      'reason', () async {
    final h = await harness(mac: false);

    await expectLater(
      h.dispatchCustom(
        _workflow('''
          - kind: ios.stripAndReexport
            with:
              exportOptionsPlist: ios/Export.plist
              frameworks: [Agora]
''', flavors: true),
      ),
      throwsA(
        isA<DispatchException>().having(
          (e) => e.message,
          'message',
          'job (main) needs ios-sign, which no paired runner offers: the job '
              'strips frameworks after the build, which XPath does not do on '
              'Linux yet.',
        ),
      ),
    );
  });

  test(
    'a job that asks for ios-sign itself gets a Mac, with no reason',
    () async {
      final h = await harness(mac: false);

      final run = await h.dispatchCustom(
        _workflow('', flavors: true).replaceFirst(
          '      job:\n',
          '      job:\n        capabilities: [ios-sign]\n',
        ),
      );

      final job = await only(h, run);
      expect(job.capabilities, ['flutter', 'ios-sign']);
      expect(job.narrowing, isEmpty);
    },
  );

  test(
    'existing workflows plan as before while Linux builds are off',
    () async {
      final h = await harness(linux: false, mac: false);

      final run = await h.dispatchCustom(_workflow(''));

      final job = await only(h, run);
      expect(job.capabilities, ['flutter', 'ios-sign']);
      expect(job.narrowing, isEmpty);
    },
  );

  // Two cases through the dispatcher: a flavor, and Shorebird iOS, whose
  // step needs ios-sign itself. iosLinuxLimits' own tests have the others.
  for (final (name, app, steps, flavors, reason)
      in <(String, AppProfile, String, bool, String)>[
        (
          'a Flutter flavor',
          demoApp,
          '',
          true,
          'the app uses the flavor dev, which Linux iOS builds do not support '
              'yet (omarchy-apple-dev: flavors)',
        ),
        (
          'Shorebird iOS',
          _plain,
          '''
          - kind: shorebird.release
            with:
              platform: ios
              shorebirdAppId: sb-1
              exportOptionsPlist: ios/Export.plist
''',
          false,
          'the job uses Shorebird iOS, which needs macOS (Shorebird iOS on '
              'Linux is not decided)',
        ),
      ]) {
    group(name, () {
      test('narrows the job to ios-sign; it waits for a Mac and says '
          'why', () async {
        final h = await harness(app: app);

        final run = await h.dispatchCustom(
          _workflow(steps, flavors: flavors),
          flavors
              ? const DispatchRequest(flavors: ['dev'])
              : const DispatchRequest(),
        );

        final job = await only(h, run);
        expect(job.capabilities, contains('ios-sign'));
        expect(job.capabilities, isNot(contains('ios-sign|ios-linux')));
        expect(job.narrowing, contains(reason));
        expect(job.state, JobState.queued);
        expect(
          job.message,
          allOf(
            startsWith('No connected runner can do '),
            contains('It needs ios-sign: '),
            contains(reason),
          ),
        );
      });

      test(
        'fails at plan time when no paired runner offers ios-sign',
        () async {
          final h = await harness(app: app, mac: false);

          await expectLater(
            h.dispatchCustom(
              _workflow(steps, flavors: flavors),
              flavors
                  ? const DispatchRequest(flavors: ['dev'])
                  : const DispatchRequest(),
            ),
            throwsA(
              isA<DispatchException>().having(
                (e) => e.message,
                'message',
                allOf(
                  startsWith('job'),
                  contains('needs ios-sign, which no paired runner offers: '),
                  contains(reason),
                ),
              ),
            ),
          );
          expect(
            await h.jobs.jobs.list(states: JobState.values.toSet()),
            isEmpty,
          );
        },
      );
    });
  }
}
