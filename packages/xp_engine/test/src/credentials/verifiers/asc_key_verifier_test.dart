import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';

void main() {
  late FakeAppStoreConnect asc;
  late AscKey? connectedWith;
  late AscKeyVerifier verifier;
  final material = CredentialMaterial.fromFields(
    CredentialKind.ascKey,
    credentialFields(CredentialKind.ascKey),
  );

  setUp(() {
    asc = FakeAppStoreConnect();
    connectedWith = null;
    verifier = AscKeyVerifier((key) {
      connectedWith = key;
      return asc;
    });
  });

  Future<VerificationResult> verify() =>
      verifier.verify(material, const CredentialTarget());

  test('is the verifier of ASC keys', () {
    expect(verifier.kind, CredentialKind.ascKey);
    expect(verifier.checksTarget, isTrue);
  });

  test('accepts a key Apple lets read an app', () async {
    final result = await verify();

    expect(result, const VerificationResult.verified(account: 'ABC123DEF4'));
    expect(asc.calls, ['verifyAccess']);
    expect(connectedWith?.keyId, 'ABC123DEF4');
  });

  test("for a flavor, the key must see the flavor's app", () async {
    const target = CredentialTarget(iosBundleId: 'com.mataa.app');

    final missing = await verifier.verify(material, target);
    asc.apps['com.mataa.app'] = const AscApp(
      id: '1',
      bundleId: 'com.mataa.app',
    );
    final found = await verifier.verify(material, target);

    expect(missing.status, CredentialStatus.rejected);
    expect(
      missing.message,
      'The API key ABC123DEF4 sees no app with the bundle id com.mataa.app '
      'in App Store Connect.',
    );
    expect(missing.fix, contains('Create the app'));
    expect(found, const VerificationResult.verified(account: 'ABC123DEF4'));
    expect(asc.calls, [
      'verifyAccess',
      'findApp com.mataa.app',
      'verifyAccess',
      'findApp com.mataa.app',
    ]);
  });

  test('rejects an expired or revoked key (401) with a fix', () async {
    asc.failure = const AscAuthException('Provided credentials are not valid.');

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('refused the API key ABC123DEF4'));
    expect(result.fix, contains('expired or was revoked'));
  });

  test('rejects a key whose role may not read apps (403)', () async {
    asc.failure = const AscForbiddenException('Forbidden');

    final result = await verify();

    expect(result.status, CredentialStatus.rejected);
    expect(result.fix, contains('App Manager'));
  });

  test('rejects a private key that cannot sign', () async {
    asc.failure = null;
    final broken = AscKeyVerifier(
      (_) => _Throwing(const FormatException('The key is not a P-256 key.')),
    );

    final result = await broken.verify(material, const CredentialTarget());

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('not a P-256 key'));
    expect(result.fix, contains('.p8'));
  });

  test('cannot tell when Apple is down or throttling', () async {
    for (final error in <AppStoreConnectException>[
      const AscServerException(503, 'Down'),
      const AscRateLimitedException('Slow down'),
    ]) {
      asc.failure = error;

      final result = await verify();

      expect(result.status, CredentialStatus.unreachable);
      expect(result.message, contains(error.message));
    }
  });
}

class _Throwing extends FakeAppStoreConnect {
  new(this.error);

  final Exception error;

  @override
  Future<void> verifyAccess() => throw error;
}
