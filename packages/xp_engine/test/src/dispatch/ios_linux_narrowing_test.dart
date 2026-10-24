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
  Future<DispatchHarness> harness({
    AppProfile app = _plain,
    bool linux = true,
    bool mac = true,
  }) async {
    final created = await DispatchHarness.create(
      apps: [app],
      linuxIosBuilds: linux,
    );
    if (mac) created.scheduler.pairedRunners = _AwayMac();
    return created;
  }

  Future<JobRecord> only(DispatchHarness h, Run run) async =>
      (await h.jobs.jobs.get(run.jobs.single.id))!;

  test('an iOS build needs a Mac or a Linux runner when nothing rules Linux '
      'out', () async {
    final h = await harness(mac: false);

    final run = await h.dispatchCustom(_workflow(''));

    final job = await only(h, run);
    expect(job.capabilities, ['flutter', 'ios-sign|ios-linux']);
    expect(job.narrowing, isEmpty);
  });

  test('the strip step needs the same, once', () async {
    final h = await harness(mac: false);

    final run = await h.dispatchCustom(
      _workflow('''
          - kind: ios.stripAndReexport
            with:
              exportOptionsPlist: ios/Export.plist
              frameworks: [Agora]
'''),
    );

    expect((await only(h, run)).capabilities, [
      'flutter',
      'ios-sign|ios-linux',
    ]);
  });

  test(
    'a job that asks for ios-sign itself gets a Mac, with no reason',
    () async {
      final h = await harness(mac: false);

      final run = await h.dispatchCustom(
        _workflow('').replaceFirst(
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
        (
          'a debug build',
          _plain,
          '''
          - kind: command
            with:
              executable: flutter
              arguments: [build, ios, --debug]
''',
          false,
          'the job makes a debug build of the iOS app, and Linux iOS builds '
              'are release builds only',
        ),
        (
          'a profile build',
          _plain,
          '''
          - kind: command
            with:
              executable: flutter
              arguments: [build, ipa, --profile]
''',
          false,
          'the job makes a profile build of the iOS app, and Linux iOS builds '
              'are release builds only',
        ),
        (
          'an app extension',
          const AppProfile(
            name: 'demo',
            path: '.',
            version: '1.2.3+45',
            flutterVersion: '3.47.6',
            hasIos: true,
            iosAppExtensions: ['Widgets'],
            flavors: [_main],
          ),
          '',
          false,
          'the app has the app extension Widgets, which Linux iOS builds do '
              'not support yet (omarchy-apple-dev: app extensions)',
        ),
        (
          'an iOS Simulator target',
          _plain,
          '''
          - kind: command
            with:
              executable: xcrun
              arguments: [simctl, list]
''',
          false,
          'the job uses the iOS Simulator, which needs macOS (Linux workflows '
              'test on an Android emulator)',
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
