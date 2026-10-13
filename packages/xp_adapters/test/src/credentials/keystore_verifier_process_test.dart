@Tags(['process'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The keystore check against the real `keytool`, with a keystore made for the
/// test. It needs a JDK and is skipped without one.
void main() {
  late Directory temp;
  late KeystoreVerifier verifier;

  final hasKeytool = Process.runSync('which', ['keytool']).exitCode == 0;

  KeystoreMaterial keystore({
    String password = 'testpass1',
    String alias = 'upload',
  }) => KeystoreMaterial(
    bytes: File(p.join(temp.path, 'up.jks')).readAsBytesSync(),
    storePassword: password,
    alias: alias,
    keyPassword: 'testpass1',
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xpath-keytool-');
    addTearDown(() => temp.deleteSync(recursive: true));
    verifier = KeystoreVerifier(
      runner: const IoProcessRunner(),
      files: DirectoryTemporaryFileStore(p.join(temp.path, 'tmp')),
    );
    if (!hasKeytool) return;
    final made = Process.runSync(
      'keytool',
      [
        '-genkeypair',
        '-keystore',
        p.join(temp.path, 'up.jks'),
        '-storetype',
        'JKS',
        '-storepass:env',
        'KS_PASS',
        '-keypass:env',
        'KS_PASS',
        '-alias',
        'upload',
        '-keyalg',
        'RSA',
        '-keysize',
        '2048',
        '-validity',
        '100',
        '-dname',
        'CN=XPath Test',
      ],
      environment: {'KS_PASS': 'testpass1'},
    );
    expect(made.exitCode, 0, reason: '${made.stderr}');
  });

  Future<VerificationResult> verify(KeystoreMaterial material) =>
      verifier.verify(material, const CredentialTarget());

  test('accepts a keystore with the right password and alias', () async {
    expect(
      await verify(keystore()),
      const VerificationResult.verified(account: 'upload'),
    );
    expect(Directory(p.join(temp.path, 'tmp')).listSync(), isEmpty);
  }, skip: hasKeytool ? false : 'keytool is not installed');

  test('rejects a wrong password', () async {
    final result = await verify(keystore(password: 'nope1234'));

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('store password is wrong'));
  }, skip: hasKeytool ? false : 'keytool is not installed');

  test('rejects an alias the keystore does not have', () async {
    final result = await verify(keystore(alias: 'nothere'));

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('no key with the alias "nothere"'));
  }, skip: hasKeytool ? false : 'keytool is not installed');

  test('rejects a file that is not a keystore', () async {
    final result = await verify(
      KeystoreMaterial(
        bytes: Uint8List.fromList([1, 2, 3]),
        storePassword: 'testpass1',
        alias: 'upload',
        keyPassword: 'testpass1',
      ),
    );

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('could not read the keystore'));
  }, skip: hasKeytool ? false : 'keytool is not installed');
}
