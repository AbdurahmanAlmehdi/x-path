import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';

String _fixture(String name) =>
    File('test/src/credentials/fixtures/$name').readAsStringSync();

final _material = AppleIdMaterial(
  appleId: 'dev@example.com',
  password: credentialFields(CredentialKind.appleId)['password'] as String,
);

void main() {
  late FakeProcessRunner runner;

  AppleIdVerifier verifier({bool isMacOS = true}) =>
      AppleIdVerifier(runner: runner, isMacOS: isMacOS);

  Future<VerificationResult> verify({bool isMacOS = true}) =>
      verifier(isMacOS: isMacOS).verify(_material, const CredentialTarget());

  setUp(() {
    runner = FakeProcessRunner(
      (call) => ProcessOutput(
        exitCode: 0,
        stdout: _fixture('altool_list_providers_ok.txt'),
      ),
    );
  });

  test('is the verifier of Apple IDs', () {
    expect(verifier().kind, CredentialKind.appleId);
  });

  test('accepts an Apple ID altool can list providers for', () async {
    final result = await verify();

    expect(
      result,
      const VerificationResult.verified(account: 'dev@example.com'),
    );
  });

  test('gives altool the password through the environment only', () async {
    await verify();

    final call = runner.calls.single;
    expect(call.executable, 'xcrun');
    expect(call.arguments, [
      'altool',
      '--list-providers',
      '-u',
      'dev@example.com',
      '-p',
      '@env:XPATH_ASC_APP_PASSWORD',
    ]);
    expect(call.environment, {'XPATH_ASC_APP_PASSWORD': 'abcd-efgh-ijkl-mnop'});
    expect(call.arguments.join(' '), isNot(contains('abcd-efgh')));
  });

  test('rejects a revoked or wrong password, with a fix', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 1,
      stderr: _fixture('altool_list_providers_bad_password.txt'),
    );

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('Unable to authenticate'));
    expect(result.fix, contains('Create a new app-specific password'));
  });

  test('rejects a failure altool reports with exit code 0', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 0,
      stdout: _fixture('altool_list_providers_bad_password.txt'),
    );

    expect((await verify()).status, CredentialStatus.rejected);
  });

  test('never repeats the password', () async {
    runner.handler = (call) => const ProcessOutput(
      exitCode: 1,
      stderr: 'ERROR: Unable to authenticate with abcd-efgh-ijkl-mnop',
    );

    final result = await verify();

    expect(result.message, isNot(contains('abcd-efgh-ijkl-mnop')));
    expect(result.message, contains('***'));
  });

  test('cannot tell when Apple is offline', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 1,
      stderr: _fixture('altool_list_providers_offline.txt'),
    );

    final result = await verify();

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('Apple could not be reached'));
  });

  test('cannot tell when altool fails for another reason', () async {
    runner.handler = (call) =>
        const ProcessOutput(exitCode: 1, stderr: 'Segmentation fault');

    final result = await verify();

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('exited with code 1'));
  });

  test('refuses a password that is not an app-specific one, unasked', () async {
    final result = await verifier().verify(
      const AppleIdMaterial(appleId: 'dev@example.com', password: 'Hunter2!'),
      const CredentialTarget(),
    );

    expect(result.status, CredentialStatus.rejected);
    expect(result.fix, contains('abcd-efgh-ijkl-mnop'));
    expect(runner.calls, isEmpty);
  });

  test('cannot check anything off macOS', () async {
    final result = await verify(isMacOS: false);

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('macOS'));
    expect(runner.calls, isEmpty);
  });

  test('cannot check without xcrun, or when altool hangs', () async {
    runner.startError = const ProcessStartException('xcrun', 'not found');

    expect((await verify()).fix, contains('xcode-select'));

    runner
      ..startError = null
      ..handler = (call) => Completer<ProcessOutput>().future;
    final hung = AppleIdVerifier(
      runner: runner,
      isMacOS: true,
      timeout: const Duration(milliseconds: 10),
    );

    final result = await hung.verify(_material, const CredentialTarget());

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('did not answer in time'));
  });
}
