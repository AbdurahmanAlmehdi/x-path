import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('SecretStoreException carries its message', () {
    const error = SecretStoreException('nope');

    expect(error.message, 'nope');
    expect(error.toString(), 'SecretStoreException: nope');
  });

  test('SecretsLockedException is a SecretStoreException', () {
    const error = SecretsLockedException('locked');

    expect(error, isA<SecretStoreException>());
    expect(error.toString(), 'SecretsLockedException: locked');
  });
}
