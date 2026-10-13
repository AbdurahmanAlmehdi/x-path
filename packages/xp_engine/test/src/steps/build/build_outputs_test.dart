import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/fake_build_files.dart';

const _app = '/work/app';
const _outputs = '$_app/build/app/outputs';

void main() {
  late FakeBuildFiles files;
  late BuildOutputs outputs;
  late DateTime since;

  setUp(() {
    files = FakeBuildFiles();
    outputs = BuildOutputs(files);
    since = files.markedAt;
  });

  Future<BuiltFile> android(ArtifactKind kind, {String? flavor = 'dev'}) =>
      outputs.android(_app, kind: kind, flavor: flavor, since: since);

  test('a file compares by path and time', () {
    final time = DateTime.utc(2026);

    expect(BuildFile('/a', modified: time), BuildFile('/a', modified: time));
    expect(
      BuildFile('/a', modified: time),
      isNot(BuildFile('/b', modified: time)),
    );
  });

  group('an APK', () {
    test('is taken from where Flutter puts it', () async {
      files.put('$_outputs/flutter-apk/app-dev-release.apk');

      final found = await android(ArtifactKind.apk);

      expect(
        (found as Fresh).file.path,
        '$_outputs/flutter-apk/app-dev-release.apk',
      );
    });

    test('is taken from where Gradle puts it', () async {
      files.put('$_outputs/apk/dev/release/app-dev-release.apk');

      expect(await android(ArtifactKind.apk), isA<Fresh>());
    });

    test('of an app without flavors has no flavor in its name', () async {
      files
        ..put('$_outputs/flutter-apk/app-release.apk')
        ..put('$_outputs/flutter-apk/app-dev-release.apk');

      final found = await android(ArtifactKind.apk, flavor: null);

      expect(
        (found as Fresh).file.path,
        '$_outputs/flutter-apk/app-release.apk',
      );
    });

    test('of another flavor is never taken', () async {
      files.put('$_outputs/flutter-apk/app-prod-release.apk');

      expect(await android(ArtifactKind.apk), isA<Missing>());
    });
  });

  group('a bundle', () {
    test('is taken from the folder of its variant', () async {
      files.put('$_outputs/bundle/devRelease/app-dev-release.aab');

      final found = await android(ArtifactKind.aab);

      expect(
        (found as Fresh).file.path,
        '$_outputs/bundle/devRelease/app-dev-release.aab',
      );
    });

    test('of an app without flavors is in the release folder', () async {
      files.put('$_outputs/bundle/release/app-release.aab');

      expect(await android(ArtifactKind.aab, flavor: null), isA<Fresh>());
    });
  });

  test(
    'the same file name anywhere below the outputs is the fallback',
    () async {
      files.put('$_outputs/moved/somewhere/app-dev-release.apk');

      final found = await android(ArtifactKind.apk);

      expect(
        (found as Fresh).file.path,
        '$_outputs/moved/somewhere/app-dev-release.apk',
      );
    },
  );

  test('nothing there is missing', () async {
    expect(await android(ArtifactKind.apk), isA<Missing>());
  });

  test('a file older than the build is stale', () async {
    files.put(
      '$_outputs/flutter-apk/app-dev-release.apk',
      modified: since.subtract(const Duration(days: 1)),
    );

    final found = await android(ArtifactKind.apk);

    expect(
      (found as Stale).file.path,
      '$_outputs/flutter-apk/app-dev-release.apk',
    );
  });

  test('a file written at the very moment of the marker is stale', () async {
    files.put('$_outputs/flutter-apk/app-dev-release.apk', modified: since);

    expect(await android(ArtifactKind.apk), isA<Stale>());
  });

  test('a fresh file wins over a stale one', () async {
    files
      ..put(
        '$_outputs/flutter-apk/app-dev-release.apk',
        modified: since.subtract(const Duration(days: 1)),
      )
      ..put('$_outputs/apk/dev/release/app-dev-release.apk');

    final found = await android(ArtifactKind.apk);

    expect(
      (found as Fresh).file.path,
      '$_outputs/apk/dev/release/app-dev-release.apk',
    );
  });

  test('the newest of several fresh files wins', () async {
    files
      ..put(
        '$_outputs/flutter-apk/app-dev-release.apk',
        modified: since.add(const Duration(minutes: 1)),
      )
      ..put(
        '$_outputs/apk/dev/release/app-dev-release.apk',
        modified: since.add(const Duration(minutes: 2)),
      );

    final found = await android(ArtifactKind.apk);

    expect(
      (found as Fresh).file.path,
      '$_outputs/apk/dev/release/app-dev-release.apk',
    );
  });

  group('an IPA', () {
    test('is the one exported by this build', () async {
      files
        ..put('$_app/build/ios/ipa/Mataa.ipa')
        ..put('$_app/build/ios/ipa/readme.txt');

      final found = await outputs.ios(_app, since: since);

      expect((found as Fresh).file.path, '$_app/build/ios/ipa/Mataa.ipa');
    });

    test('left by an earlier build is stale', () async {
      files.put(
        '$_app/build/ios/ipa/Mataa.ipa',
        modified: since.subtract(const Duration(hours: 1)),
      );

      expect(await outputs.ios(_app, since: since), isA<Stale>());
    });

    test('that was not exported is missing', () async {
      expect(await outputs.ios(_app, since: since), isA<Missing>());
    });
  });
}
