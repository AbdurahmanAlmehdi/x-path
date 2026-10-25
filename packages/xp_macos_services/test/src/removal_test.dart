import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (_) => null;
    messenger.setMockMethodCallHandler(macosServicesChannel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(
    () => messenger.setMockMethodCallHandler(macosServicesChannel, null),
  );

  test('names the engine data folder and the Keychain prefix', () {
    expect(
      engineDataDirectory('/Users/owner'),
      '/Users/owner/Library/Application Support/XPath',
    );
    expect(keychainServicePrefix, 'ly.abdurahman.xpath');
  });

  group('SystemKeychainWiper', () {
    late List<List<String>> runs;
    late int exitCode;

    SystemKeychainWiper wiper() => SystemKeychainWiper(
      run: (executable, arguments) async {
        runs.add([executable, ...arguments]);
        return ProcessResult(0, exitCode, '', 'item busy\n');
      },
    );

    setUp(() {
      runs = [];
      exitCode = 0;
    });

    test(
      "deletes the app's items itself and the engine's with security",
      () async {
        answer = (call) => switch (call.method) {
          'keychainItems' => [
            {'service': 'ly.abdurahman.xpath.app', 'account': 'engine.local'},
            {'service': 'ly.abdurahman.xpath.credentials', 'account': 'gh'},
          ],
          _ => null,
        };

        expect(await wiper().wipe(), 2);
        expect(calls.map((call) => call.method), [
          'keychainItems',
          'keychainDelete',
        ]);
        expect(calls.first.arguments, {'prefix': 'ly.abdurahman.xpath'});
        expect(calls.last.arguments, {'account': 'engine.local'});
        expect(runs, [
          [
            '/usr/bin/security',
            'delete-generic-password',
            '-s',
            'ly.abdurahman.xpath.credentials',
            '-a',
            'gh',
          ],
        ]);
      },
    );

    test('deletes nothing when there is nothing', () async {
      expect(await wiper().wipe(), 0);
      expect(runs, isEmpty);
    });

    test('reports what security refused', () async {
      exitCode = 44;
      answer = (_) => [
        {'service': 'ly.abdurahman.xpath.master', 'account': 'master-key'},
      ];

      await expectLater(
        wiper().wipe(),
        throwsA(
          isA<MacosServiceException>().having(
            (error) => error.message,
            'message',
            contains('item busy'),
          ),
        ),
      );
    });

    test('reports a Keychain the runner cannot list', () async {
      answer = (_) => throw PlatformException(code: 'locked');

      await expectLater(
        wiper().wipe(),
        throwsA(
          isA<MacosServiceException>().having(
            (error) => error.code,
            'code',
            'locked',
          ),
        ),
      );
    });

    test('runs the real security by default', () {
      expect(const SystemKeychainWiper().security, '/usr/bin/security');
    });
  });

  group('FileSystemDataWiper', () {
    test('deletes the folders that exist', () async {
      final root = Directory.systemTemp.createTempSync('xp_wipe_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final engine = Directory('${root.path}/engine')..createSync();
      File('${engine.path}/xpath.db').writeAsStringSync('x');
      final missing = '${root.path}/missing';

      final wiper = FileSystemDataWiper([engine.path, missing]);

      expect(await wiper.wipe(), [engine.path]);
      expect(engine.existsSync(), isFalse);
      expect(wiper.folders, [engine.path, missing]);
    });
  });

  group('MethodChannelRunningApp', () {
    const app = MethodChannelRunningApp();

    test('reads the version, trashes the app and quits', () async {
      answer = (call) => switch (call.method) {
        'appVersion' => '1.0.0 (7)',
        'appMoveToTrash' => true,
        _ => null,
      };

      expect(await app.version(), '1.0.0 (7)');
      expect(await app.moveToTrash(), isTrue);
      await app.quit();
      await app.setKeepRunning(keep: false);
      expect(calls.map((call) => call.method), [
        'appVersion',
        'appMoveToTrash',
        'appQuit',
        'appKeepRunning',
      ]);
      expect(calls.last.arguments, {'keep': false});
    });

    test('reads nothing as no version and no trash', () async {
      expect(await app.version(), '');
      expect(await app.moveToTrash(), isFalse);
    });
  });

  group('MethodChannelAppMenu', () {
    test('turns XPath ▸ Settings… into a request', () async {
      final menu = MethodChannelAppMenu();
      final requests = <void>[];
      final subscription = menu.settingsRequests.listen(requests.add);
      addTearDown(subscription.cancel);

      Future<void> send(String method) async {
        final done = Completer<void>();
        await messenger.handlePlatformMessage(
          appMenuChannelName,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) => done.complete(),
        );
        await done.future;
      }

      await send('settings');
      await send('unknown');
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(1));
      expect(menu.channel.name, appMenuChannelName);
    });
  });
}
