import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/app/app_preferences.dart';

void main() {
  late Directory directory;
  late String path;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_preferences');
    path = '${directory.path}/support/preferences.json';
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('starts with the defaults when there is no file', () async {
    final preferences = await AppPreferences.load(path);

    expect(preferences.keepRunning, isTrue);
    expect(preferences.mutedNotices, isEmpty);
    expect(preferences.lastDestination('eng_1'), isNull);
  });

  test('keeps what it is told across launches', () async {
    final preferences = await AppPreferences.load(path);
    await preferences.setKeepRunning(keep: false);
    await preferences.setMutedNotices({'jobSucceeded', 'releaseLive'});
    await preferences.setLastDestination('eng_1', 'runners');
    await preferences.setLastDestination('eng_2', 'settings');

    final again = await AppPreferences.load(path);
    expect(again.keepRunning, isFalse);
    expect(again.mutedNotices, {'jobSucceeded', 'releaseLive'});
    expect(again.lastDestination('eng_1'), 'runners');
    expect(again.lastDestination('eng_2'), 'settings');
  });

  test('reads a broken file as no preference', () async {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('[not an object');
    expect((await AppPreferences.load(path)).keepRunning, isTrue);

    File(path).writeAsStringSync('[]');
    expect((await AppPreferences.load(path)).keepRunning, isTrue);
  });

  test('in memory, writes nothing to disk', () async {
    final preferences = AppPreferences({'keepRunning': false});
    await preferences.setLastDestination('eng_1', 'home');

    expect(preferences.keepRunning, isFalse);
    expect(preferences.lastDestination('eng_1'), 'home');
    expect(File(path).existsSync(), isFalse);
  });
}
