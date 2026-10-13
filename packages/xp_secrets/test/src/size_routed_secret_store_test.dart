import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

import '../helpers/memory_secret_store.dart';

/// [count] bytes, none of them the same as the next one.
Uint8List _bytes(int count) =>
    Uint8List.fromList(List.generate(count, (i) => (i * 7 + 3) % 256));

const int _limit = SizeRoutedSecretStore.maxSmallEncodedLength;

void main() {
  late MemorySecretStore small;
  late MemorySecretStore large;
  late SizeRoutedSecretStore store;

  setUp(() {
    small = MemorySecretStore();
    large = MemorySecretStore();
    store = SizeRoutedSecretStore(small: small, large: large);
  });

  group('encodedLength', () {
    test('is the length of the base64 form', () {
      for (final count in [0, 1, 2, 3, 4, 5, 100, 1535, 1536, 1537, 16384]) {
        expect(
          SizeRoutedSecretStore.encodedLength(count),
          base64.encode(Uint8List(count)).length,
          reason: '$count bytes',
        );
      }
    });

    test('the limit is 2 KB of base64', () {
      expect(_limit, 2048);
    });
  });

  group('write', () {
    test('keeps an empty value in the small store', () async {
      await store.writeBytes('k', const []);

      expect(small.values, {'k': isEmpty});
      expect(large.values, isEmpty);
    });

    test(
      'keeps the largest value whose base64 fits in the small one',
      () async {
        final value = _bytes(1536);
        expect(SizeRoutedSecretStore.encodedLength(value.length), _limit);

        await store.writeBytes('k', value);

        expect(small.values['k'], value);
        expect(large.values, isEmpty);
      },
    );

    test('sends one byte more to the large store', () async {
      final value = _bytes(1537);
      expect(SizeRoutedSecretStore.encodedLength(value.length), _limit + 4);

      await store.writeBytes('k', value);

      expect(large.values['k'], value);
      expect(small.values, isEmpty);
    });

    test('routes text by its UTF-8 size', () async {
      final big = 'é' * 1000; // 2000 bytes

      await store.write('big', big);
      await store.write('little', 'é' * 100);

      expect(large.values.keys, ['big']);
      expect(small.values.keys, ['little']);
      expect(await store.read('big'), big);
      expect(await store.read('little'), 'é' * 100);
    });

    test('moves a secret that grows to the large store', () async {
      await store.writeBytes('k', _bytes(10));
      small.operations.clear();
      large.operations.clear();

      await store.writeBytes('k', _bytes(5000));

      expect(small.values, isEmpty);
      expect(large.values['k'], _bytes(5000));
      expect(large.operations, ['write k']);
      expect(small.operations, ['delete k']);
    });

    test('moves a secret that shrinks back to the small store', () async {
      await store.writeBytes('k', _bytes(5000));

      await store.writeBytes('k', _bytes(10));

      expect(large.values, isEmpty);
      expect(small.values['k'], _bytes(10));
    });

    test('keeps the old copy when the new one cannot be written', () async {
      await store.writeBytes('k', _bytes(10));
      large.failure = const SecretStoreException('disk full');

      await expectLater(
        store.writeBytes('k', _bytes(5000)),
        throwsA(isA<SecretStoreException>()),
      );

      expect(small.values['k'], _bytes(10));
      expect(await store.readBytes('k'), _bytes(10));
    });

    test('rejects a bad key', () async {
      await expectLater(store.writeBytes('', _bytes(1)), throwsArgumentError);
    });
  });

  group('read', () {
    test('is null when neither store has the key', () async {
      expect(await store.readBytes('k'), isNull);
      expect(await store.read('k'), isNull);
    });

    test(
      'asks the small store first and skips the large one on a hit',
      () async {
        await store.writeBytes('k', _bytes(10));
        large.operations.clear();

        expect(await store.readBytes('k'), _bytes(10));
        expect(large.operations, isEmpty);
      },
    );

    test('falls back to the large store', () async {
      await store.writeBytes('k', _bytes(5000));

      expect(await store.readBytes('k'), _bytes(5000));
    });

    test('prefers the small copy of a key that is in both', () async {
      small.values['k'] = _bytes(3);
      large.values['k'] = _bytes(5000);

      expect(await store.readBytes('k'), _bytes(3));
    });

    test('rejects a bad key', () async {
      await expectLater(store.readBytes('a\nb'), throwsArgumentError);
    });
  });

  group('delete', () {
    test('removes the key from both stores', () async {
      small.values['k'] = _bytes(3);
      large.values['k'] = _bytes(5000);
      small.values['other'] = _bytes(1);

      await store.delete('k');

      expect(small.values.keys, ['other']);
      expect(large.values, isEmpty);
    });

    test('does nothing for a missing key', () async {
      await store.delete('k');

      expect(small.operations, ['delete k']);
      expect(large.operations, ['delete k']);
    });

    test('rejects a bad key', () async {
      await expectLater(store.delete(''), throwsArgumentError);
    });
  });

  group('locked', () {
    const locked = SecretsLockedException('The Keychain is locked.');

    test('a locked small store locks the whole store', () async {
      small.failure = locked;

      await expectLater(
        store.writeBytes('k', _bytes(10)),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(store.status, SecretsStatus.locked);
    });

    test('a large secret cannot be written to a locked file store', () async {
      large.failure = locked;

      await expectLater(
        store.writeBytes('k', _bytes(5000)),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(store.status, SecretsStatus.locked);
    });

    test('a locked large store locks a read the small one misses', () async {
      large.failure = locked;

      await expectLater(
        store.readBytes('k'),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(store.status, SecretsStatus.locked);
    });

    test('a locked store unlocks with the next success, and says so', () async {
      final changes = <SecretsStatus>[];
      store.statusChanges.listen(changes.add);
      small.failure = locked;
      await expectLater(
        store.delete('k'),
        throwsA(isA<SecretsLockedException>()),
      );

      small.failure = null;
      await store.delete('k');

      expect(store.status, SecretsStatus.unlocked);
      expect(changes, [SecretsStatus.locked, SecretsStatus.unlocked]);
    });
  });

  test(
    'operations run one at a time, so a moving secret is never lost',
    () async {
      final writes = [
        store.writeBytes('k', _bytes(5000)),
        store.writeBytes('k', _bytes(10)),
        store.writeBytes('k', _bytes(6000)),
        store.writeBytes('k', _bytes(20)),
      ];
      final read = store.readBytes('k');
      await Future.wait(writes);

      expect(await read, _bytes(20));
      expect(small.values['k'], _bytes(20));
      expect(large.values, isEmpty);
    },
  );
}
