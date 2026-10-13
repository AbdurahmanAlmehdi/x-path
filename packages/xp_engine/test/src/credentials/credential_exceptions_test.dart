import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('an exception describes itself with its fix', () {
    const error = CredentialRejectedException(
      'Revoked.',
      fix: 'Make a new one.',
    );

    expect(error.described, 'Revoked. Make a new one.');
    expect(error.toString(), 'CredentialException: Revoked.');
    expect(const CredentialNotFoundException('Gone.').described, 'Gone.');
  });
}
