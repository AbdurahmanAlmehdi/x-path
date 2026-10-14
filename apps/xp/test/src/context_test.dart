import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:test/test.dart';
import 'package:xp/src/config/client_secret_store.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/update/update_check.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  test(
    'the system context reads the real environment and standard streams',
    () {
      final logger = Logger();

      final context = XpContext.system(logger: logger);

      expect(context.logger, same(logger));
      expect(context.environment, Platform.environment);
      expect(context.updateCheck, isA<UpdateCheck>());
      expect(context.logIdle, const Duration(milliseconds: 750));
      expect(context.config.directory, endsWith('xpath'));
    },
  );

  test('the system context makes real clients for a connection', () {
    final context = XpContext.system();

    final client = context.clientFactory(
      Connection(url: Uri.parse('http://127.0.0.1:1'), token: 't'),
    );
    addTearDown(client.close);

    expect(client.baseUrl, Uri.parse('http://127.0.0.1:1'));
    expect(client.token, 't');
  });

  test(
    'the system context keeps tokens in the secret store of the machine',
    () async {
      final directory = Directory.systemTemp.createTempSync('xp_context');
      addTearDown(() => directory.deleteSync(recursive: true));
      // The file store, so that no Keychain is touched on a Mac.
      final context = XpContext.system(
        environment: {
          configDirVariable: directory.path,
          fileSecretsVariable: '1',
          engineUrlVariable: 'http://e:1',
        },
      );

      await context.config.saveToken(DeviceTokenKind.cli, 'secret-token');
      final connection = await context.config.connection(DeviceTokenKind.cli);

      expect(connection.token, 'secret-token');
      expect(connection.url, Uri.parse('http://e:1'));
      expect(File('${directory.path}/secrets.enc').existsSync(), isTrue);
    },
  );
}
