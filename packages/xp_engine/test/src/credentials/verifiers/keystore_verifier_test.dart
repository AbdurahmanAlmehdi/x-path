import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';

String _fixture(String name) =>
    File('test/src/credentials/fixtures/$name').readAsStringSync();

final _material = CredentialMaterial.fromFields(
  CredentialKind.keystore,
  credentialFields(CredentialKind.keystore),
);

void main() {
  late FakeProcessRunner runner;
  late MemoryTemporaryFiles files;

  KeystoreVerifier verifier() => KeystoreVerifier(runner: runner, files: files);

  Future<VerificationResult> verify() =>
      verifier().verify(_material, const CredentialTarget());

  setUp(() {
    files = MemoryTemporaryFiles();
    runner = FakeProcessRunner(
      (call) => ProcessOutput(
        exitCode: 0,
        stdout: _fixture('keytool_list_ok_stdout.txt'),
        stderr: _fixture('keytool_list_ok.txt'),
      ),
    );
  });

  test('is the verifier of keystores', () {
    expect(verifier().kind, CredentialKind.keystore);
  });

  test('accepts a keystore keytool can list the alias of', () async {
    expect(
      await verify(),
      const VerificationResult.verified(account: 'upload'),
    );
  });

  test('gives keytool the file and the password by environment', () async {
    await verify();

    final call = runner.calls.single;
    expect(call.executable, 'keytool');
    expect(call.arguments, [
      '-list',
      '-keystore',
      '/tmp/keystore-1',
      '-storepass:env',
      'XPATH_KEYSTORE_STOREPASS',
      '-alias',
      'upload',
    ]);
    expect(call.environment, {'XPATH_KEYSTORE_STOREPASS': 'store-pass'});
    expect(call.arguments.join(' '), isNot(contains('store-pass')));
    expect(files.created.single, [1, 2, 3, 4, 250]);
  });

  test('deletes the file whatever keytool says', () async {
    await verify();
    runner.handler = (call) =>
        const ProcessOutput(exitCode: 1, stderr: 'keytool error: x');
    await verify();
    runner.startError = const ProcessStartException('keytool', 'not found');
    await verify();

    expect(files.deleted, [
      '/tmp/keystore-1',
      '/tmp/keystore-2',
      '/tmp/keystore-3',
    ]);
  });

  test('rejects a wrong store password', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 1,
      stderr: _fixture('keytool_wrong_password.txt'),
    );

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('store password is wrong'));
    expect(result.fix, contains('right store password'));
  });

  test('rejects an alias the keystore does not have', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 1,
      stderr: _fixture('keytool_missing_alias.txt'),
    );

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('no key with the alias "upload"'));
  });

  test('rejects a file that is not a keystore', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 1,
      stderr: _fixture('keytool_not_a_keystore.txt'),
    );

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('could not read the keystore'));
  });

  test('cannot check without keytool, or when it hangs', () async {
    runner.startError = const ProcessStartException('keytool', 'not found');

    final missing = await verify();

    expect(missing.status, CredentialStatus.unreachable);
    expect(missing.fix, contains('JDK'));

    runner
      ..startError = null
      ..handler = (call) => Completer<ProcessOutput>().future;
    final hung = KeystoreVerifier(
      runner: runner,
      files: files,
      timeout: const Duration(milliseconds: 10),
    );

    final result = await hung.verify(_material, const CredentialTarget());

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('did not answer in time'));
  });
}
