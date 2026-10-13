import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

class _Store extends TrackingSecretStore {
  @override
  Future<String?> read(String key) => track(() async {
    checkKey(key);
    throw const SecretStoreException('read failed');
  });

  @override
  Future<void> write(String key, String value) => track(() async {
    if (value == 'locked') throw const SecretsLockedException('locked');
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
