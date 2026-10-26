import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/memory_secret_store.dart';

const _appId = '8b7e4a52-3c7e-4d57-bd3b-1f2b1b6c9c11';
const _success = '{"status": "success", "data": {}}';

class _LockedSecrets extends MemorySecretStore {
  @override
  Future<String?> read(String key) =>
      throw const SecretsLockedException('The Keychain is locked.');
}

void main() {
  late FakeProcessRunner runner;
  late MemorySecretStore secrets;

  ShorebirdCliPatches adapter([SecretStore? store]) =>
      ShorebirdCliPatches(runner: runner, secrets: store ?? secrets);

  Future<void> change(
    PatchAction action, {
    String? tokenSecret = 'shorebird.token',
    SecretStore? store,
  }) => adapter(store).change(
    appId: _appId,
    releaseVersion: '1.2.3+45',
    patchNumber: 2,
    action: action,
    tokenSecret: tokenSecret,
  );

  Matcher fails(Object message) => throwsA(
    isA<ShorebirdPatchesException>().having(
      (e) => e.message,
      'message',
      message,
    ),
  );

  setUp(() {
    secrets = MemorySecretStore()..values['shorebird.token'] = 'sb_api_secret';
    runner = FakeProcessRunner(
      (call) => const ProcessOutput(exitCode: 0, stdout: _success),
    );
  });

  test('promotes and rolls back with the key in the environment', () async {
    await change(PatchAction.promote);
    await change(PatchAction.rollback, tokenSecret: null);

    expect(
      [for (final call in runner.calls) call.arguments],
      [
        for (final action in ['promote', 'rollback'])
          [
            '--json',
            'patches',
            action,
            '--app-id',
            _appId,
            '--release-version',
            '1.2.3+45',
            '--patch-number',
            '2',
          ],
      ],
    );
    expect(runner.calls.first.environment, {
      'CI': 'true',
      'SHOREBIRD_TOKEN': 'sb_api_secret',
    });
    expect(runner.calls.last.environment, {'CI': 'true'});
  });

  test('says what the CLI said, without the key', () async {
    runner = FakeProcessRunner(
      (call) => const ProcessOutput(
        exitCode: 70,
        stderr: 'Patch 2 not found for sb_api_secret',
      ),
    );

    await expectLater(
      change(PatchAction.promote),
      fails('Patch 2 not found for ***'),
    );
    await expectLater(
      change(PatchAction.promote, tokenSecret: null),
      fails('Patch 2 not found for sb_api_secret'),
    );
  });

  test('says when the CLI is missing or too slow', () async {
    runner.startError = const ProcessStartException('shorebird', 'not found');
    await expectLater(
      change(PatchAction.promote),
      fails(contains('not installed')),
    );

    runner
      ..startError = null
      ..handler = (call) => Completer<ProcessOutput>().future;
    await expectLater(
      ShorebirdCliPatches(
        runner: runner,
        secrets: secrets,
        timeout: const Duration(milliseconds: 10),
      ).change(
        appId: _appId,
        releaseVersion: '1.2.3+45',
        patchNumber: 2,
        action: PatchAction.rollback,
      ),
      fails(contains('did not answer')),
    );
  });

  test('says when the key cannot be read or is gone', () async {
    await expectLater(
      change(PatchAction.promote, store: _LockedSecrets()),
      fails(contains('The Keychain is locked.')),
    );
    await expectLater(
      change(PatchAction.promote, store: MemorySecretStore()),
      fails(contains('is gone')),
    );
    expect(runner.calls, isEmpty);
  });
}
