import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';

ServiceAccountMaterial _material(CredentialKind kind) =>
    CredentialMaterial.fromFields(kind, credentialFields(kind))
        as ServiceAccountMaterial;

void main() {
  group('PlayServiceAccountVerifier', () {
    late FakeGooglePlay play;
    late PlayServiceAccountVerifier verifier;
    final material = _material(CredentialKind.playSa);
    const target = CredentialTarget(androidAppId: 'com.mataa.app');

    setUp(() {
      play = FakeGooglePlay();
      verifier = PlayServiceAccountVerifier((_) => play);
    });

    test('is the verifier of Play service accounts', () {
      expect(verifier.kind, CredentialKind.playSa);
    });

    test('accepts an account that can read the internal track', () async {
      final result = await verifier.verify(material, target);

      expect(
        result,
        VerificationResult.verified(account: testServiceAccount.clientEmail),
      );
      expect(play.calls, ['verifyAccess', 'releases com.mataa.app internal']);
    });

    test(
      'checks the token alone for a flavor without an application id',
      () async {
        final result = await verifier.verify(
          material,
          const CredentialTarget(),
        );

        expect(result.status, CredentialStatus.verified);
        expect(play.calls, ['verifyAccess']);
      },
    );

    test('rejects an account Google refuses', () async {
      play.failures['verifyAccess'] = const PlayAuthException(
        'Invalid JWT Signature.',
        reason: 'invalid_grant',
      );

      final result = await verifier.verify(material, target);

      expect(result.status, CredentialStatus.rejected);
      expect(result.message, contains('Invalid JWT Signature'));
      expect(result.fix, contains('service account key'));
    });

    test('rejects an account that is not invited for the app', () async {
      play.failures['releases'] = const PlayForbiddenException('No access');

      final result = await verifier.verify(material, target);

      expect(result.status, CredentialStatus.rejected);
      expect(result.message, contains('may not read com.mataa.app'));
      expect(result.fix, contains('Play Console'));
    });

    test('rejects an application id Play does not know', () async {
      play.failures['releases'] = const PlayNotFoundException('Not found');

      final result = await verifier.verify(material, target);

      expect(result.status, CredentialStatus.rejected);
      expect(result.message, contains('does not know com.mataa.app'));
    });

    test('cannot tell when Google is down', () async {
      play.failures['verifyAccess'] = const PlayServerException(503, 'Down');

      final result = await verifier.verify(material, target);

      expect(result.status, CredentialStatus.unreachable);
      expect(result.message, contains('Down'));
    });
  });

  group('FirebaseServiceAccountVerifier', () {
    late FakeFirebaseAppDistribution firebase;
    late FirebaseServiceAccountVerifier verifier;
    final material = _material(CredentialKind.firebaseSa);

    setUp(() {
      firebase = FakeFirebaseAppDistribution();
      verifier = FirebaseServiceAccountVerifier((_) => firebase);
    });

    Future<VerificationResult> verify() =>
        verifier.verify(material, const CredentialTarget());

    test('is the verifier of Firebase service accounts', () {
      expect(verifier.kind, CredentialKind.firebaseSa);
    });

    test('accepts an account Google gives a token', () async {
      expect(
        await verify(),
        VerificationResult.verified(account: testServiceAccount.clientEmail),
      );
      expect(firebase.calls, ['verifyAccess']);
    });

    test('rejects an account Google refuses', () async {
      firebase.failures['verifyAccess'] = const FirebaseAuthException(
        'Invalid JWT Signature.',
      );

      final result = await verify();

      expect(result.status, CredentialStatus.rejected);
      expect(result.message, contains('Invalid JWT Signature'));
      expect(result.fix, contains('service account key'));
    });

    test('cannot tell when Google is down', () async {
      firebase.failures['verifyAccess'] = const FirebaseServerException(
        503,
        'Down',
      );

      expect((await verify()).status, CredentialStatus.unreachable);
    });
  });
}
