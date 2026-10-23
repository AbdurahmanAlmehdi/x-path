import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/runner_helpers.dart';

void main() {
  late RunnerClient client;
  late StringBuffer out;
  late RunnerLog log;
  late StreamSubscription<void> following;

  setUp(() async {
    client = await RunnerClient.start();
    out = StringBuffer();
    log = RunnerLog(out, client.engine.runnerService);
    following = log.follow(client.engine.events);
  });

  tearDown(() async {
    await following.cancel();
    await client.close();
  });

  Future<List<String>> linesOnceThere(String text) async {
    for (var i = 0; i < 200 && !out.toString().contains(text); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return out.toString().trim().split('\n');
  }

  test('writes a line when a runner connects, changes and leaves', () async {
    final stream = await client.online();
    await stream.close();

    final lines = await linesOnceThere('disconnected');

    const connected =
        'runner "mac-mini" connected: xp 1.0.0, macos arm64, 2 slots, '
        'flutter, ios-sign (no android: no Android SDK in ANDROID_HOME, '
        'ANDROID_SDK_ROOT or ~/Library/Android/sdk)';
    expect(lines, [
      'runner "mac-mini" now offers flutter, ios-sign (was nothing)',
      connected,
      'runner "mac-mini" disconnected (the connection dropped)',
    ]);
  });

  test('says what it can of a runner it does not know', () async {
    client.engine.events
      ..append(
        const RunnerConnected(
          runnerId: 'rnr_ghost',
          name: 'ghost',
          capabilities: [],
          slots: 1,
        ),
      )
      ..append(const RunnerDisconnected(runnerId: 'rnr_ghost', name: 'ghost'))
      ..append(const RunnerRevoked(runnerId: 'rnr_ghost', name: 'ghost'));

    final lines = await linesOnceThere('ghost" disconnected');

    expect(lines, ['runner "ghost" connected', 'runner "ghost" disconnected']);
  });

  test('writes refused connections', () {
    log.refused('10.0.0.7', 'an unknown or revoked credential (401)');

    expect(
      out.toString(),
      'refused a runner connection from 10.0.0.7: an unknown or revoked '
      'credential (401)\n',
    );
  });
}
