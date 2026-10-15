import 'dart:io';

import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  group('isLaunchedByLaunchd', () {
    test('is true only when the LaunchAgent of the app set it', () {
      expect(isLaunchedByLaunchd({launchdEnvironmentKey: '1'}), isTrue);
      expect(isLaunchedByLaunchd({launchdEnvironmentKey: '0'}), isFalse);
      expect(isLaunchedByLaunchd({}), isFalse);
      expect(launchdEnvironmentKey, 'XPATH_LAUNCHD');
    });

    test('is set by the LaunchAgent the app bundles', () {
      final plist = File(
        '../xp_desktop/macos/Runner/Library/LaunchAgents/'
        'ly.abdurahman.xpath.xpd.plist',
      ).readAsStringSync();

      expect(
        plist,
        matches(
          RegExp('<key>$launchdEnvironmentKey</key>\\s*<string>1</string>'),
        ),
      );
    });
  });

  group('withToolDirectories', () {
    const home = '/Users/owner';

    test('puts the tool folders that exist and are missing in front', () {
      final environment = withToolDirectories({
        'HOME': home,
        'PATH': '/opt/homebrew/bin:/usr/bin:/bin',
        'OTHER': 'kept',
      }, isDirectory: (path) => path != '$home/fvm/default/bin');

      expect(
        environment['PATH'],
        [
          '$home/.shorebird/bin',
          '$home/.pub-cache/bin',
          '/usr/local/bin',
          '/opt/homebrew/bin',
          '/usr/bin',
          '/bin',
        ].join(':'),
      );
      expect(environment['OTHER'], 'kept');
    });

    test('builds a PATH when there is none', () {
      final environment = withToolDirectories({
        'HOME': home,
      }, isDirectory: (path) => path == '/opt/homebrew/bin');

      expect(environment['PATH'], '/opt/homebrew/bin');
    });

    test('leaves the environment alone when nothing is missing', () {
      final given = {'HOME': home, 'PATH': '/usr/bin'};

      expect(withToolDirectories(given, isDirectory: (_) => false), given);
      expect(
        withToolDirectories({'PATH': '/usr/bin'}, isDirectory: (_) => true),
        {'PATH': '/usr/bin'},
      );
      expect(withToolDirectories({'HOME': ''}, isDirectory: (_) => true), {
        'HOME': '',
      });
    });

    test('looks at the file system by default', () {
      final root = Directory.systemTemp.createTempSync('xpd_tools_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/.pub-cache/bin').createSync(recursive: true);

      final path = withToolDirectories({
        'HOME': root.path,
        'PATH': '/usr/bin',
      })['PATH']!;

      expect(path, startsWith('${root.path}/.pub-cache/bin:'));
      expect(path, isNot(contains('.shorebird')));
      expect(path, endsWith(':/usr/bin'));
    });

    test('lists the folders in PATH order', () {
      expect(toolDirectories(home), [
        '$home/.shorebird/bin',
        '$home/.pub-cache/bin',
        '$home/fvm/default/bin',
        '/opt/homebrew/bin',
        '/usr/local/bin',
      ]);
    });
  });

  group('LogFileSink', () {
    late Directory root;
    late String path;
    final now = DateTime.utc(2026, 10, 16, 9, 30);

    setUp(() {
      root = Directory.systemTemp.createTempSync('xpd_log_');
      path = serveLogPath('${root.path}/data');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('lives in the service logs of the data directory', () {
      expect(serveLogPath('/data'), '/data/service-logs/xpd.log');
    });

    test('appends whole lines with the time they were written', () async {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('earlier\n');
      final sink = LogFileSink.open(path, now: () => now)
        ..write('xpd ')
        ..writeln('listening')
        ..writeAll(['a', 'b'], ', ')
        ..writeCharCode(0x0a)
        ..write('two\nlines\nand a rest');
      await sink.close();

      const at = '2026-10-16T09:30:00.000Z';
      expect(File(path).readAsStringSync(), '''
earlier
$at xpd listening
$at a, b
$at two
$at lines
$at and a rest
''');
    });

    test('moves a log that grew too large aside first', () async {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old old old\n');
      final sink = LogFileSink.open(path, now: () => now, maxBytes: 4)
        ..writeln('new');
      await sink.close();

      expect(File('$path.1').readAsStringSync(), 'old old old\n');
      expect(File(path).readAsStringSync(), '2026-10-16T09:30:00.000Z new\n');
    });

    test('closes cleanly with nothing written', () async {
      await LogFileSink.open(path).close();

      expect(File(path).readAsStringSync(), isEmpty);
    });
  });
}
