import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/memory_secret_store.dart';

void main() {
  late MemorySecretStore secrets;

  GitHubTokenImporter importerAnswering(
    FakeProcessRunner runner, {
    Duration? timeout,
  }) => GitHubTokenImporter(
    runner: runner,
    secrets: secrets,
    timeout: timeout ?? const Duration(seconds: 5),
  );

  setUp(() => secrets = MemorySecretStore());

  test('stores the trimmed output of gh auth token', () async {
    final runner = FakeProcessRunner(
      (_) => const ProcessOutput(exitCode: 0, stdout: 'gho_abc123\n'),
    );

    await importerAnswering(runner).import();

    expect(secrets.values, {githubTokenSecretKey: 'gho_abc123'});
    final call = runner.calls.single;
    expect(call.executable, 'gh');
    expect(call.arguments, ['auth', 'token']);
    expect(call.environment, containsPair('GH_PROMPT_DISABLED', '1'));
  });

  test('reads the token without storing it, as a GitHubCliToken', () async {
    final runner = FakeProcessRunner(
      (_) => const ProcessOutput(exitCode: 0, stdout: 'gho_abc123\n'),
    );
    final GitHubCliToken cli = importerAnswering(runner);

    expect(await cli.read(), 'gho_abc123');
    expect(secrets.values, isEmpty);
  });

  test('says how to fix a failure', () {
    const error = GitHubTokenImportException('gh auth token failed.');

    expect(error, isA<GitHubCliTokenException>());
    expect(error.fix, contains('gh auth login'));
    expect('$error', 'GitHubTokenImportException: gh auth token failed.');
  });

  test('runs the configured gh', () async {
    final runner = FakeProcessRunner(
      (_) => const ProcessOutput(exitCode: 0, stdout: 'gho_abc123\n'),
    );

    await GitHubTokenImporter(
      runner: runner,
      secrets: secrets,
      ghExecutable: '/opt/homebrew/bin/gh',
    ).import();

    expect(runner.calls.single.executable, '/opt/homebrew/bin/gh');
  });

  test('fails when gh is not logged in and stores nothing', () async {
    final runner = FakeProcessRunner(
      (_) => const ProcessOutput(
        exitCode: 1,
        stderr: 'You are not logged into any GitHub hosts.\n',
      ),
    );

    await expectLater(
      importerAnswering(runner).import(),
      throwsA(
        isA<GitHubTokenImportException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('exit 1'), contains('not logged in')),
        ),
      ),
    );
    expect(secrets.values, isEmpty);
  });

  test('fails when gh prints no token or something else', () async {
    for (final stdout in ['', '\n', 'two words', 'a\nb']) {
      final runner = FakeProcessRunner(
        (_) => ProcessOutput(exitCode: 0, stdout: stdout),
      );

      await expectLater(
        importerAnswering(runner).import(),
        throwsA(isA<GitHubTokenImportException>()),
        reason: stdout,
      );
    }
    expect(secrets.values, isEmpty);
  });

  test('fails when gh cannot be started', () async {
    final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0))
      ..startError = const ProcessStartException('gh', 'not found');

    await expectLater(
      importerAnswering(runner).import(),
      throwsA(
        isA<GitHubTokenImportException>().having(
          (e) => e.message,
          'message',
          'Cannot run gh: not found',
        ),
      ),
    );
  });

  test('fails when gh hangs', () async {
    final runner = FakeProcessRunner((_) => Completer<ProcessOutput>().future);

    await expectLater(
      importerAnswering(
        runner,
        timeout: const Duration(milliseconds: 50),
      ).import(),
      throwsA(isA<GitHubTokenImportException>()),
    );
    expect(runner.calls.single.killed, isTrue);
  });
}
