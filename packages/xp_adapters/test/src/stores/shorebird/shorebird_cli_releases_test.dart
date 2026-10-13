import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/memory_secret_store.dart';

const _appId = '8b7e4a52-3c7e-4d57-bd3b-1f2b1b6c9c11';

String _fixture(String name) =>
    File('test/src/stores/shorebird/fixtures/$name').readAsStringSync();

class _LockedSecrets extends MemorySecretStore {
  @override
  Future<String?> read(String key) =>
      throw const SecretsLockedException('The Keychain is locked.');
}

void main() {
  late FakeProcessRunner runner;
  late MemorySecretStore secrets;

  ShorebirdCliReleases adapter() =>
      ShorebirdCliReleases(runner: runner, secrets: secrets);

  setUp(() {
    secrets = MemorySecretStore()..values['shorebird.token'] = 'sb_api_secret';
    runner = FakeProcessRunner(
      (call) =>
          ProcessOutput(exitCode: 0, stdout: _fixture('releases_list.json')),
    );
  });

  group('releases', () {
    test('reads the releases of the documented JSON', () async {
      final releases = await adapter().releases(_appId);

      expect(releases, [
        ShorebirdRelease(
          version: AppVersion.parse('1.2.3+45'),
          flutterVersion: '3.35.4',
          activePlatforms: const {'android'},
        ),
        ShorebirdRelease(
          version: AppVersion.parse('1.2.2+44'),
          flutterVersion: null,
          activePlatforms: const {'android', 'ios'},
        ),
        // A release without a version is skipped; one with no statuses
        // is complete for no platform.
      ]);
    });

    test(
      'lists the app without prompts and without a token argument',
      () async {
        await adapter().releases(_appId, tokenSecret: 'shorebird.token');

        final call = runner.calls.single;
        expect(call.executable, 'shorebird');
        expect(call.arguments, [
          '--json',
          'releases',
          'list',
          '--app-id',
          _appId,
        ]);
        expect(call.environment, {
          'CI': 'true',
          'SHOREBIRD_TOKEN': 'sb_api_secret',
        });
        expect(call.arguments.join(' '), isNot(contains('sb_api')));
      },
    );

    test('uses the login of the machine without a token secret', () async {
      await adapter().releases(_appId);

      expect(runner.calls.single.environment, {'CI': 'true'});
    });

    test('is null when the token cannot be read', () async {
      expect(await adapter().releases(_appId, tokenSecret: 'other'), isNull);
      secrets = _LockedSecrets();
      expect(await adapter().releases(_appId, tokenSecret: 'x'), isNull);
      expect(runner.calls, isEmpty);
    });

    test('is null when the CLI fails', () async {
      runner.handler = (_) => const ProcessOutput(
        exitCode: 70,
        stdout: '{"status": "error", "error": {"code": "fetch_failed"}}',
      );

      expect(await adapter().releases(_appId), isNull);
    });

    test('is null when the CLI is missing', () async {
      runner.startError = const ProcessStartException('shorebird', 'not found');

      expect(await adapter().releases(_appId), isNull);
    });

    test('is null when the CLI is too slow', () async {
      runner.handler = (_) => Completer<ProcessOutput>().future;
      final slow = ShorebirdCliReleases(
        runner: runner,
        secrets: secrets,
        timeout: const Duration(milliseconds: 20),
      );

      expect(await slow.releases(_appId), isNull);
      expect(runner.calls.single.killed, isTrue);
    });

    test('is null for output that is not the documented JSON', () async {
      for (final stdout in [
        'Not logged in.',
        '[]',
        '{"status": "error"}',
        '{"status": "success"}',
        '{"status": "success", "data": {"releases": "none"}}',
      ]) {
        runner.handler = (_) => ProcessOutput(exitCode: 0, stdout: stdout);

        expect(await adapter().releases(_appId), isNull, reason: stdout);
      }
    });

    test('is empty for an app without releases', () async {
      runner.handler = (_) => const ProcessOutput(
        exitCode: 0,
        stdout: '{"status": "success", "data": {"releases": []}}',
      );

      expect(await adapter().releases(_appId), isEmpty);
    });
  });
}
