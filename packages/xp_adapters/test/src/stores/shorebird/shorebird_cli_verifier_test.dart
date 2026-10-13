import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

String _fixture(String name) =>
    File('test/src/stores/shorebird/fixtures/$name').readAsStringSync();

void main() {
  late FakeProcessRunner runner;
  const token = 'sb_api_abc123secret';

  ShorebirdCliVerifier verifier() =>
      ShorebirdCliVerifier(ShorebirdCli(runner: runner));

  Future<VerificationResult> verify([String key = token]) => verifier().verify(
    TokenMaterial(CredentialKind.shorebird, key),
    const CredentialTarget(),
  );

  setUp(() {
    runner = FakeProcessRunner(
      (call) =>
          ProcessOutput(exitCode: 0, stdout: _fixture('account_whoami.json')),
    );
  });

  test('is the verifier of Shorebird keys', () {
    expect(verifier().kind, CredentialKind.shorebird);
  });

  test('accepts a key the CLI can read the account with', () async {
    final result = await verify();

    expect(
      result,
      const VerificationResult.verified(account: 'dev@example.com'),
    );
  });

  test('runs whoami with the key in the environment only', () async {
    await verify();

    final call = runner.calls.single;
    expect(call.arguments, ['account', 'whoami', '--json']);
    expect(call.environment, {'CI': 'true', 'SHOREBIRD_TOKEN': token});
    expect(call.arguments.join(' '), isNot(contains('sb_api')));
  });

  test('accepts a key whose account has no email', () async {
    runner.handler = (call) => const ProcessOutput(
      exitCode: 0,
      stdout: '{"status": "success", "data": {"email": ""}}',
    );

    expect(await verify(), const VerificationResult.verified());
  });

  test('refuses a key without the sb_api_ prefix, unasked', () async {
    final result = await verify('login-ci-token');

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('sb_api_'));
    expect(result.fix, contains('2026-10-01'));
    expect(runner.calls, isEmpty);
  });

  test('rejects a revoked or expired key, with a fix', () async {
    runner.handler = (call) => ProcessOutput(
      exitCode: 1,
      stdout: _fixture('account_whoami_not_logged_in.json'),
    );

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('not logged in'));
    expect(result.fix, contains('Create a new API key'));
  });

  test('never repeats the key', () async {
    runner.handler = (call) => const ProcessOutput(
      exitCode: 1,
      stderr: 'Invalid token sb_api_abc123secret',
    );

    final result = await verify();

    expect(result.message, isNot(contains('abc123secret')));
    expect(result.message, contains('***'));
  });

  test('cuts a long message', () async {
    runner.handler = (call) =>
        ProcessOutput(exitCode: 1, stderr: 'invalid ${'x' * 500}');

    expect((await verify()).message!.length, lessThan(300));
  });

  test('cannot tell when the network fails', () async {
    runner.handler = (call) => const ProcessOutput(
      exitCode: 1,
      stderr: 'SocketException: Failed host lookup: api.shorebird.dev',
    );

    final result = await verify();

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('Failed host lookup'));
  });

  test('cannot tell when the CLI fails for another reason', () async {
    runner.handler = (call) => const ProcessOutput(exitCode: 70);

    final result = await verify();

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('no output'));
  });

  test('cannot tell without the CLI, or when it hangs', () async {
    runner.startError = const ProcessStartException('shorebird', 'not found');

    final missing = await verify();

    expect(missing.status, CredentialStatus.unreachable);
    expect(missing.fix, contains('Install Shorebird'));

    runner
      ..startError = null
      ..handler = (call) => Completer<ProcessOutput>().future;
    final slow = ShorebirdCliVerifier(
      ShorebirdCli(runner: runner, timeout: const Duration(milliseconds: 10)),
    );

    final result = await slow.verify(
      const TokenMaterial(CredentialKind.shorebird, token),
      const CredentialTarget(),
    );

    expect(result.status, CredentialStatus.unreachable);
    expect(result.message, contains('did not answer in time'));
  });
}
