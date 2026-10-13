import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

import '../../helpers/memory_secret_store.dart';

class _Counting implements Random {
  var _next = 0;

  @override
  int nextInt(int max) => _next++ % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  late MemorySecretStore keychain;
  late KeychainMasterKeySource source;

  setUp(() {
    keychain = MemorySecretStore();
    source = KeychainMasterKeySource(store: keychain, random: _Counting());
  });

  test('creates a 32 byte key in the Keychain on first use', () async {
    final key = await source.load(createIfMissing: true);

    expect(key, List.generate(masterKeyLength, (i) => i));
    expect(keychain.values.keys, [KeychainMasterKeySource.defaultAccount]);
    expect(keychain.values.values.single, key);
  });

  test('uses a secure random source by default', () async {
    final real = KeychainMasterKeySource(store: keychain);

    final key = await real.load(createIfMissing: true);

    expect(key, hasLength(masterKeyLength));
    expect(key.toSet().length, greaterThan(1));
  });

  test('reads the key it made earlier instead of making a new one', () async {
    final first = await source.load(createIfMissing: true);

    final again = KeychainMasterKeySource(store: keychain);

    expect(await again.load(createIfMissing: false), first);
    expect(await again.load(createIfMissing: true), first);
  });

  test('asks the Keychain once and then remembers the key', () async {
    await source.load(createIfMissing: true);
    keychain.operations.clear();

    await source.load(createIfMissing: false);

    expect(keychain.operations, isEmpty);
  });

  test('does not make a key where secrets already exist', () async {
    await expectLater(
      source.load(createIfMissing: false),
      throwsA(
        isA<SecretsLockedException>().having(
          (e) => e.message,
          'message',
          contains('missing from the Keychain'),
        ),
      ),
    );
    expect(keychain.values, isEmpty);
  });

  test('refuses a stored key of the wrong size', () async {
    await keychain.writeBytes(KeychainMasterKeySource.defaultAccount, [1, 2]);

    await expectLater(
      source.load(createIfMissing: true),
      throwsA(
        isA<SecretsLockedException>().having(
          (e) => e.message,
          'message',
          contains('exactly $masterKeyLength bytes, not 2'),
        ),
      ),
    );
  });

  test('uses the account it is given', () async {
    final custom = KeychainMasterKeySource(
      store: keychain,
      account: 'other',
      random: _Counting(),
    );

    await custom.load(createIfMissing: true);

    expect(keychain.values.keys, ['other']);
    expect(custom.account, 'other');
  });

  test('a locked Keychain is a locked key', () async {
    keychain.failure = const SecretsLockedException('locked');

    await expectLater(
      source.load(createIfMissing: true),
      throwsA(isA<SecretsLockedException>()),
    );
  });
}
