import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/dispatch/ios_linux_limits.dart';
import 'package:xp_engine/xp_engine.dart';

const _app = AppProfile(name: 'demo', path: '.', hasIos: true);

const _shorebird =
    'the job uses Shorebird iOS, which needs macOS (Shorebird iOS on Linux is '
    'not decided)';
const _debug =
    'the job makes a debug build of the iOS app, and Linux iOS builds are '
    'release builds only';
const _profile =
    'the job makes a profile build of the iOS app, and Linux iOS builds are '
    'release builds only';
const _simulator =
    'the job uses the iOS Simulator, which needs macOS (Linux workflows test '
    'on an Android emulator)';
const _unsigned =
    'the flavor has no Apple Distribution identity with an App Store Connect '
    'API key assigned, which Linux runners sign with (xp credentials add '
    '--kind apple_distribution)';
const _signing = {
  'linuxSigning': {'ASC_PROFILE': 'identity.profile:ly.demo'},
};
const _widgets =
    'the app has the app extension Widgets, which Linux iOS builds do not '
    'support yet (omarchy-apple-dev: app extensions)';

StepPlan _step(String kind, [Map<String, dynamic> input = const {}]) =>
    StepPlan(kind: kind, input: input, sideEffect: false);

StepPlan _command(String executable, List<String> arguments) =>
    _step('command', {'executable': executable, 'arguments': arguments});

void main() {
  test('an unflavored release build has none', () {
    expect(
      iosLinuxLimits([
        _step('git.checkout'),
        _step('build.ios', {'version': '1.0.0+1', ..._signing}),
        _step('shorebird.release', {'platform': 'android'}),
        _command('flutter', ['build', 'ios', '--release']),
      ], _app),
      isEmpty,
    );
  });

  test('a flavor and an entry point build on Linux (omarchy-apple-dev '
      'FLAVOR and TARGET)', () {
    expect(
      iosLinuxLimits([
        _step('build.ios', {
          'flavor': 'prod',
          'target': 'lib/main_prod.dart',
          ..._signing,
        }),
      ], _app),
      isEmpty,
    );
  });

  test('the strip step', () {
    expect(
      iosLinuxLimits([
        _step('build.ios', {'target': 'lib/main_prod.dart', ..._signing}),
        _step('ios.stripAndReexport'),
      ], _app),
      [contains('the job strips frameworks after the build')],
    );
  });

  test('what the scan found about the project', () {
    expect(
      iosLinuxLimits(
        [_step('build.ios', _signing)],
        const AppProfile(
          name: 'demo',
          path: '.',
          iosLinuxLimits: ['the app pins Flutter 3.44.2'],
        ),
      ),
      ['the app pins Flutter 3.44.2'],
    );
  });

  test("the scan's own reasons for the flavor a step builds", () {
    const icon = 'its configuration Release-dev uses a multi-size icon set';
    const app = AppProfile(
      name: 'demo',
      path: '.',
      flavors: [
        FlavorProfile(
          name: 'dev',
          entrypoint: 'lib/main_dev.dart',
          iosLinuxLimits: [icon],
        ),
        FlavorProfile(name: 'prod', entrypoint: 'lib/main_prod.dart'),
      ],
    );

    expect(
      iosLinuxLimits([
        _step('build.ios', {'flavor': 'dev', ..._signing}),
        _step('ios.stripAndReexport', {'flavor': 'dev'}),
      ], app),
      [icon, contains('the job strips frameworks after the build')],
    );
    expect(
      iosLinuxLimits([
        _step('build.ios', {'flavor': 'prod', ..._signing}),
      ], app),
      isEmpty,
    );
    expect(
      iosLinuxLimits([
        _step('build.ios', {'flavor': 'staging', ..._signing}),
      ], app),
      isEmpty,
      reason: 'a flavor the scan does not know has no limits of its own',
    );
    expect(iosLinuxLimits([_step('build.ios', _signing)], app), isEmpty);
  });

  test("the scan's own reasons for the flavor of an app without flavors", () {
    const app = AppProfile(
      name: 'demo',
      path: '.',
      flavors: [
        FlavorProfile(
          name: 'default',
          implicit: true,
          entrypoint: 'lib/main.dart',
          iosLinuxLimits: ['its configuration Release uses a multi-size set'],
        ),
      ],
    );

    expect(iosLinuxLimits([_step('build.ios', _signing)], app), [
      'its configuration Release uses a multi-size set',
    ]);
    expect(iosLinuxLimits([_step('git.checkout')], app), isEmpty);
  });

  test('a build the flavor cannot sign on Linux, with a flavor too', () {
    expect(iosLinuxLimits([_step('build.ios')], _app), [_unsigned]);
    expect(
      iosLinuxLimits([
        _step('build.ios', {'flavor': 'prod'}),
      ], _app),
      [_unsigned],
    );
  });

  test('Shorebird iOS, a release or a patch', () {
    for (final kind in ['shorebird.release', 'shorebird.patch']) {
      expect(
        iosLinuxLimits([
          _step(kind, {'platform': 'ios'}),
        ], _app),
        [_shorebird],
      );
    }
  });

  test('a debug or a profile build of the iOS app', () {
    expect(
      iosLinuxLimits([
        _command('/opt/flutter/bin/flutter', ['build', 'ipa', '--debug']),
        _command('flutter', ['build', 'ios', '--profile']),
        _command('flutter', ['build', 'apk', '--debug']),
      ], _app),
      [_debug, _profile],
    );
  });

  test('an iOS Simulator target, however it is named', () {
    for (final (executable, arguments) in [
      ('xcrun', ['simctl', 'boot', 'iPhone 17']),
      ('flutter', ['build', 'ios', '--simulator']),
      ('xcodebuild', ['-sdk', 'iphonesimulator']),
      ('xcodebuild', ['-destination', 'platform=iOS Simulator,name=iPhone']),
    ]) {
      expect(iosLinuxLimits([_command(executable, arguments)], _app), [
        _simulator,
      ], reason: '$executable $arguments');
    }
  });

  test('a command without arguments', () {
    expect(
      iosLinuxLimits([
        _step('command', {'executable': 'ls'}),
      ], _app),
      isEmpty,
    );
  });

  test('an app with Linux iOS builds turned off, before every other '
      'reason', () {
    const off = AppProfile(
      name: 'demo',
      path: '.',
      iosLinux: false,
      iosLinuxLimits: ['the app pins Flutter 3.44.2'],
    );

    expect(iosLinuxLimits([_step('build.ios', _signing)], off), [
      'Linux iOS builds are turned off for this app',
      'the app pins Flutter 3.44.2',
    ]);
    expect(
      iosLinuxLimits(
        const [],
        const AppProfile(name: 'a', path: '.', iosLinux: false),
      ),
      [iosLinuxOff],
    );
  });

  test('app extensions of the Xcode project', () {
    expect(
      iosLinuxLimits(
        const [],
        const AppProfile(
          name: 'demo',
          path: '.',
          iosAppExtensions: ['Widgets'],
        ),
      ),
      [_widgets],
    );
    expect(
      iosLinuxLimits(
        const [],
        const AppProfile(
          name: 'demo',
          path: '.',
          iosAppExtensions: ['Widgets', 'Share'],
        ),
      ).single,
      startsWith('the app has the app extensions Widgets, Share,'),
    );
  });
}
