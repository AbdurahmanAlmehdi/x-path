import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

class _Store extends TrackingSecretStore {
  /// What [readBytes] returns for the key `bytes`.
  List<int>? bytes;

  /// The last value [writeBytes] got.
  List<int>? written;

  @override
  Future<Uint8List?> readBytes(String key) => track(() async {
    checkKey(key);
    if (key == 'bytes') {
      final stored = bytes;
      return stored == null ? null : Uint8List.fromList(stored);
    }
    throw const SecretStoreException('read failed');
  });

  @override
  Future<void> writeBytes(String key, List<int> value) => track(() async {
    written = value;
    if (utf8.decode(value, allowMalformed: true) == 'locked') {
      throw const SecretsLockedException('locked');
    }
  });

  @override
  Future<void> delete(String key) async {}
}

void main() {
  late _Store store;
  late List<SecretsStatus> changes;

  setUp(() {
    store = _Store();
    changes = [];
    store.statusChanges.listen(changes.add);
  });

  test('a store starts out unlocked', () {
    expect(store.status, SecretsStatus.unlocked);
  });

  test('a locked failure locks the store and a success unlocks it', () async {
    await expectLater(
      store.write('k', 'locked'),
      throwsA(isA<SecretsLockedException>()),
    );
    expect(store.status, SecretsStatus.locked);

    await store.write('k', 'fine');
    expect(store.status, SecretsStatus.unlocked);
    expect(changes, [SecretsStatus.locked, SecretsStatus.unlocked]);
  });

  test('only a change of status is announced', () async {
    await store.write('k', 'fine');
    await store.write('k', 'fine');
    await expectLater(
      store.write('k', 'locked'),
      throwsA(isA<SecretsLockedException>()),
    );
    await expectLater(
      store.write('k', 'locked'),
      throwsA(isA<SecretsLockedException>()),
    );

    expect(changes, [SecretsStatus.locked]);
  });

  test('another failure leaves the status alone', () async {
    await expectLater(store.read('k'), throwsA(isA<SecretStoreException>()));

    expect(store.status, SecretsStatus.unlocked);
    expect(changes, isEmpty);
  });

  group('text', () {
    test('write stores the UTF-8 bytes', () async {
      await store.write('k', 'é✓');

      expect(store.written, utf8.encode('é✓'));
    });

    test('read decodes the UTF-8 bytes', () async {
      store.bytes = utf8.encode('é✓\n');

      expect(await store.read('bytes'), 'é✓\n');
    });

    test('read keeps a leading byte order mark', () async {
      store.bytes = [0xEF, 0xBB, 0xBF, 0x41];

      expect(await store.read('bytes'), '\uFEFFA');
    });

    test('read is null where readBytes is', () async {
      expect(await store.read('bytes'), isNull);
    });

    test('read refuses bytes that are not UTF-8', () async {
      store.bytes = [0xFF, 0xFE, 0x00];

      await expectLater(
        store.read('bytes'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            contains('readBytes'),
          ),
        ),
      );
    });
  });

  group('serialized', () {
    test('runs operations one after the other, even after a failure', () async {
      final order = <String>[];
      final first = store.serialized(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add('first');
        throw StateError('boom');
      });
      final second = store.serialized(() async => order.add('second'));

      await expectLater(first, throwsStateError);
      await second;
      expect(order, ['first', 'second']);
    });
  });

  group('checkKey', () {
    test('rejects an empty key', () async {
      await expectLater(store.read(''), throwsArgumentError);
    });

    test('rejects line breaks and other control characters', () async {
      for (final key in ['a\nb', 'a\rb', 'a\u0000b', 'a\u007fb']) {
        await expectLater(store.read(key), throwsArgumentError);
      }
    });

    test('accepts quotes, backslashes, spaces and unicode', () async {
      await expectLater(
        store.read(r'a "b" \ ç ✓'),
        throwsA(isA<SecretStoreException>()),
      );
    });
  });
}
