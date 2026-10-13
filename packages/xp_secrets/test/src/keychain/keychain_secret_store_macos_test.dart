@Tags(['macos'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

import '../../helpers/real_process.dart';

/// A value no other process could contain: its tail is random at run time.
String _randomValue() {
  final random = Random.secure();
  final tail = List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'S3c "q" \\ $tail \$HOME\'';
}

void main() {
  late Directory directory;
  late String keychain;
  late FakeProcessRunner runner;
  late KeychainSecretStore store;
  // Every process listing taken while a `security -i` was alive.
  late List<String> listings;
  // The command line of that `security -i` in each listing.
  late List<String?> securityLines;

  void security(List<String> arguments) {
    final result = Process.runSync('/usr/bin/security', arguments);
    if (result.exitCode != 0) {
      fail('security ${arguments.first} failed: ${result.stderr}');
    }
  }

  setUp(() {
    listings = [];
    securityLines = [];
    directory = Directory.systemTemp.createTempSync('xp_keychain_');
    keychain = '${directory.path}/xpath-test.keychain-db';
    // Only ever a temporary keychain, never the login keychain.
    security(['create-keychain', '-p', 'test-only', keychain]);
    security(['unlock-keychain', '-p', 'test-only', keychain]);
    runner = FakeProcessRunner(
      (call) => runForReal(
        call,
        whileAlive: (pid) async {
          // `security -i` runs the line it was sent and then waits for more
          // input, so it is alive until its stdin is closed.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final ps = await Process.run('ps', ['-axww', '-o', 'pid=,args=']);
          final listing = ps.stdout as String;
          listings.add(listing);
          securityLines.add(
            const LineSplitter()
                .convert(listing)
                .map((line) => line.trim())
                .where((line) => line.startsWith('$pid '))
                .firstOrNull,
          );
        },
      ),
    );
    store = KeychainSecretStore(runner: runner, keychainPath: keychain);
  });

  tearDown(() {
    Process.runSync('/usr/bin/security', ['delete-keychain', keychain]);
    directory.deleteSync(recursive: true);
  });

  void expectNeverInProcessList(String value) {
    expect(listings, isNotEmpty);
    for (final listing in listings) {
      expect(listing, isNot(contains(value)));
      expect(listing, isNot(contains(base64.encode(utf8.encode(value)))));
    }
    // The listing did contain our `security -i`, so it was looked at.
    for (final line in securityLines) {
      expect(line, endsWith('/usr/bin/security -i'));
    }
  }

  test('writes, reads and deletes an item without the value in ps', () async {
    final value = _randomValue();

    await store.write('asc.key', value);
    expect(await store.read('asc.key'), value);
    await store.delete('asc.key');
    expect(await store.read('asc.key'), isNull);

    expect(listings, hasLength(4), reason: 'one security -i per operation');
    expectNeverInProcessList(value);
  });

  test('round-trips multi-line and non-ASCII values', () async {
    final value =
        '-----BEGIN PRIVATE KEY-----\n${_randomValue()}\r\nçé ✓\n'
        '-----END PRIVATE KEY-----\n';

    await store.write('play.sa', value);

    expect(await store.read('play.sa'), value);
    expectNeverInProcessList(value);
  });

  test('replaces the value of an existing item', () async {
    await store.write('k', 'first-value');
    await store.write('k', 'second-value');

    expect(await store.read('k'), 'second-value');
  });

  test('reads null and deletes quietly when there is no item', () async {
    expect(await store.read('missing'), isNull);
    await store.delete('missing');
    expect(store.status, SecretsStatus.unlocked);
  });
}
