import 'dart:io';

import 'package:test/test.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/test_env.dart';

void main() {
  late Directory directory;
  late MemoryTokenVault vault;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_config_test');
    vault = MemoryTokenVault();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  XpConfig config([Map<String, String> environment = const {}]) => XpConfig(
    directory: '${directory.path}/xpath',
    environment: environment,
    openVault: () => vault,
  );

  group('XpConfig.directoryFor', () {
    test('uses XP_CONFIG_DIR first', () {
      expect(
        XpConfig.directoryFor({configDirVariable: '/etc/xp'}, '/home/me'),
        '/etc/xp',
      );
    });

    test('then XDG_CONFIG_HOME', () {
      expect(
        XpConfig.directoryFor({'XDG_CONFIG_HOME': '/cfg'}, '/home/me'),
        '/cfg/xpath',
      );
    });

    test('then ~/.config/xpath', () {
      expect(XpConfig.directoryFor({}, '/home/me'), '/home/me/.config/xpath');
      expect(
        XpConfig.directoryFor({
          configDirVariable: '',
          'XDG_CONFIG_HOME': '',
        }, '/h'),
        '/h/.config/xpath',
      );
    });
  });

  group('engineUrl', () {
    test('is null when nothing was saved', () async {
      expect(await config().engineUrl(), isNull);
    });

    test('comes back as saved, in a file with no secret in it', () async {
      final saved = config();
      await saved.saveEngineUrl(Uri.parse('http://127.0.0.1:7480'));

      expect(await config().engineUrl(), Uri.parse('http://127.0.0.1:7480'));
      final file = File('${directory.path}/xpath/xp.json');
      expect(file.readAsStringSync(), contains('127.0.0.1:7480'));
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('is overridden by XP_ENGINE_URL', () async {
      await config().saveEngineUrl(Uri.parse('http://saved:1'));

      expect(
        await config({engineUrlVariable: 'other:9'}).engineUrl(),
        Uri.parse('http://other:9'),
      );
    });

    test('an unreadable file is a NotConnectedException', () async {
      Directory('${directory.path}/xpath').createSync();
      File('${directory.path}/xpath/xp.json').writeAsStringSync('[1]');

      await expectLater(
        config().engineUrl(),
        throwsA(isA<NotConnectedException>()),
      );
      File('${directory.path}/xpath/xp.json').writeAsStringSync('{');
      await expectLater(
        config().engineUrl(),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('an engine that is not a string is ignored', () async {
      Directory('${directory.path}/xpath').createSync();
      File('${directory.path}/xpath/xp.json')
          .writeAsStringSync('{"engine": 3}');

      expect(await config().engineUrl(), isNull);
    });

    test('keeps the other settings when it saves', () async {
      Directory('${directory.path}/xpath').createSync();
      File('${directory.path}/xpath/xp.json').writeAsStringSync('{"x": 1}');

      await config().saveEngineUrl(Uri.parse('http://a:1'));

      expect(
        File('${directory.path}/xpath/xp.json').readAsStringSync(),
        allOf(contains('"x": 1'), contains('http://a:1')),
      );
    });
  });

  group('parseEngineUrl', () {
    test('reads http and https URLs', () {
      expect(parseEngineUrl('https://xp.example.com'), isA<Uri>());
      expect(parseEngineUrl(' http://a:1 ').port, 1);
    });

    test('takes a bare host and port as http', () {
      expect(
        parseEngineUrl('127.0.0.1:7480').toString(),
        'http://127.0.0.1:7480',
      );
    });

    test('refuses anything else', () {
      expect(() => parseEngineUrl('ftp://a'), throwsFormatException);
      expect(() => parseEngineUrl('http://'), throwsFormatException);
    });
  });

  group('token', () {
    test('comes from the environment first', () async {
      vault.tokens[DeviceTokenKind.cli] = 'saved';

      expect(
        await config({tokenVariable: 'env'}).token(DeviceTokenKind.cli),
        'env',
      );
      expect(
        await config({mcpTokenVariable: 'm'}).token(DeviceTokenKind.mcp),
        'm',
      );
    });

    test('then from the vault', () async {
      vault.tokens[DeviceTokenKind.cli] = 'saved';

      expect(await config().token(DeviceTokenKind.cli), 'saved');
      expect(await config().token(DeviceTokenKind.mcp), isNull);
    });

    test('is saved in the vault', () async {
      await config().saveToken(DeviceTokenKind.mcp, 'm1');

      expect(vault.tokens[DeviceTokenKind.mcp], 'm1');
    });

    test('a locked secret store says what to do', () async {
      vault.failWith = const SecretsLockedException('The Keychain is locked.');

      await expectLater(
        config().token(DeviceTokenKind.cli),
        throwsA(
          isA<NotConnectedException>().having(
            (e) => e.message,
            'message',
            allOf(contains('locked'), contains(tokenVariable)),
          ),
        ),
      );
      await expectLater(
        config().saveToken(DeviceTokenKind.cli, 't'),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });

  group('connection', () {
    test('has the engine and the token', () async {
      final connection = await config({
        engineUrlVariable: 'http://e:1',
        tokenVariable: 't',
      }).connection(DeviceTokenKind.cli);

      expect(connection.url, Uri.parse('http://e:1'));
      expect(connection.token, 't');
    });

    test('without an engine says to connect', () async {
      await expectLater(
        config({tokenVariable: 't'}).connection(DeviceTokenKind.cli),
        throwsA(
          isA<NotConnectedException>().having(
            (e) => '$e',
            'message',
            contains('xp connect'),
          ),
        ),
      );
    });

    test('without a token names the option for its kind', () async {
      final env = {engineUrlVariable: 'http://e:1'};

      await expectLater(
        config(env).connection(DeviceTokenKind.cli),
        throwsA(
          isA<NotConnectedException>().having(
            (e) => e.message,
            'message',
            allOf(contains('--token'), contains(tokenVariable)),
          ),
        ),
      );
      await expectLater(
        config(env).connection(DeviceTokenKind.mcp),
        throwsA(
          isA<NotConnectedException>().having(
            (e) => e.message,
            'message',
            allOf(contains('--mcp-token'), contains(mcpTokenVariable)),
          ),
        ),
      );
    });
  });
}
