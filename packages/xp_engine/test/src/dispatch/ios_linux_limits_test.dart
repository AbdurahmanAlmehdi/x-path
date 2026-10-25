import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/dispatch/ios_linux_limits.dart';
import 'package:xp_engine/xp_engine.dart';

const _app = AppProfile(name: 'demo', path: '.', hasIos: true);

const _flavor =
    'the app uses the flavor prod, which Linux iOS builds do not support yet '
    '(omarchy-apple-dev: flavors)';
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
        _step('build.ios', {'version': '1.0.0+1'}),
        _step('ios.stripAndReexport'),
        _step('shorebird.release', {'platform': 'android'}),
        _command('flutter', ['build', 'ios', '--release']),
      ], _app),
      isEmpty,
    );
  });

  test('a flavor of the build or the strip step, once', () {
    expect(
      iosLinuxLimits([
        _step('build.ios', {'flavor': 'prod'}),
        _step('ios.stripAndReexport', {'flavor': 'prod'}),
      ], _app),
      [_flavor],
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
