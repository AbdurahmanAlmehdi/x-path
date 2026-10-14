import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('xp_android_');
    addTearDown(() => home.deleteSync(recursive: true));
  });

  String sdk(String relative, {String marker = 'platform-tools'}) {
    final directory = Directory(p.join(home.path, relative, marker))
      ..createSync(recursive: true);
    return directory.parent.path;
  }

  Future<String?> locate({Map<String, String> environment = const {}}) =>
      DirectoryAndroidSdk(environment: environment, home: home.path).locate();

  test('finds nothing on a machine without an SDK', () async {
    expect(await locate(), isNull);
    expect(
      await const DirectoryAndroidSdk(environment: {}, home: null).locate(),
      isNull,
    );
  });

  test('takes ANDROID_HOME, then ANDROID_SDK_ROOT', () async {
    final first = sdk('one');
    final second = sdk('two', marker: 'cmdline-tools');

    expect(
      await locate(
        environment: {'ANDROID_HOME': first, 'ANDROID_SDK_ROOT': second},
      ),
      first,
    );
    expect(await locate(environment: {'ANDROID_SDK_ROOT': second}), second);
  });

  test('looks in the default places of Android Studio', () async {
    final mac = sdk('Library/Android/sdk', marker: 'build-tools');
    expect(await locate(), mac);
    Directory(mac).deleteSync(recursive: true);
    final linux = sdk('Android/Sdk');
    expect(await locate(), linux);
  });

  test('skips a folder that is no SDK and an empty variable', () async {
    final empty = Directory(p.join(home.path, 'empty'))..createSync();
    final real = sdk('real');

    expect(await locate(environment: {'ANDROID_HOME': ''}), isNull);
    expect(
      await locate(
        environment: {'ANDROID_HOME': empty.path, 'ANDROID_SDK_ROOT': real},
      ),
      real,
    );
  });
}
