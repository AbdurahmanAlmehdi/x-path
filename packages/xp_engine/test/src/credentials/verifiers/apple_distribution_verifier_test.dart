import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';

void main() {
  late InMemoryCredentialRepository credentials;
  late BytesSecretStore secrets;
  late FakeAppStoreConnect asc;
  late ManualClock clock;
  late AppleDistributionVerifier verifier;
  final material = CredentialMaterial.fromFields(
    CredentialKind.appleDistribution,
    credentialFields(CredentialKind.appleDistribution),
  );
  const target = CredentialTarget(flavorId: 'flv_1');

  Future<void> giveFlavorAnAscKey() async {
    await credentials.put(
      const AssignedCredential(
        flavor: testFlavor,
        credential: CredentialRecord(
          id: 'crd_asc',
          name: 'ASC',
          kind: CredentialKind.ascKey,
          secretKey: 'asc',
          account: 'ABC123DEF4',
        ),
      ),
    );
    await CredentialMaterial.fromFields(
      CredentialKind.ascKey,
      credentialFields(CredentialKind.ascKey),
    ).write(secrets, 'asc');
  }

  setUp(() {
    credentials = InMemoryCredentialRepository([testFlavor]);
    secrets = BytesSecretStore();
    asc = FakeAppStoreConnect();
    clock = ManualClock(DateTime.utc(2026, 10, 25));
    verifier = AppleDistributionVerifier(
      credentials: credentials,
      secrets: secrets,
      connect: (_) => asc,
      clock: clock,
    );
  });

  test('is the verifier of Apple Distribution identities', () {
    expect(verifier.kind, CredentialKind.appleDistribution);
    expect(verifier.checksTarget, isTrue);
  });

  test('accepts a certificate that has not expired, on its own', () async {
    final result = await verifier.verify(material, const CredentialTarget());

    expect(
      result,
      const VerificationResult.verified(
        account: 'Apple Distribution: XPath Test (TEAM123456)',
      ),
    );
    expect(asc.calls, isEmpty);
  });

  test('refuses a certificate that has expired', () async {
    clock.advance(const Duration(days: 365 * 101));

    final result = await verifier.verify(material, const CredentialTarget());

    expect(result.status, CredentialStatus.rejected);
    expect(
      result.message,
      'The certificate Apple Distribution: XPath Test (TEAM123456) expired '
      'on 2126-10-01.',
    );
  });

  test('for a flavor, needs its App Store Connect key', () async {
    final result = await verifier.verify(material, target);

    expect(result.status, CredentialStatus.rejected);
    expect(result.message, contains('no App Store Connect API key'));
    expect(result.fix, contains('xp credentials verify'));
  });

  test('for a flavor, refuses a certificate App Store Connect does not '
      'list', () async {
    await giveFlavorAnAscKey();
    asc.certificates.add(
      const AscCertificate(id: 'other', serialNumber: '0BADBAD'),
    );

    final result = await verifier.verify(material, target);

    expect(result.status, CredentialStatus.rejected);
    expect(
      result.message,
      'App Store Connect lists no distribution certificate with the serial '
      'number A1B2C3D4E5F in the team of the API key ABC123DEF4: it was '
      'revoked, or is of another team.',
    );
    expect(asc.calls, ['distributionCertificates']);
  });

  test('for a flavor, accepts a certificate the team has', () async {
    await giveFlavorAnAscKey();
    asc.certificates.add(
      const AscCertificate(id: 'c1', serialNumber: '0A1B2C3D4E5F'),
    );

    final result = await verifier.verify(material, target);

    expect(
      result,
      const VerificationResult.verified(
        account: 'Apple Distribution: XPath Test (TEAM123456)',
      ),
    );
  });

  test('says what App Store Connect refused, or that it could not '
      'tell', () async {
    await giveFlavorAnAscKey();
    final results = <VerificationResult>[];
    for (final failure in const <AppStoreConnectException>[
      AscAuthException('revoked'),
      AscForbiddenException('no role'),
      AscServerException(503, 'down'),
    ]) {
      asc.failure = failure;
      results.add(await verifier.verify(material, target));
    }

    expect(
      [for (final result in results) result.status],
      [
        CredentialStatus.rejected,
        CredentialStatus.rejected,
        CredentialStatus.unreachable,
      ],
    );
    expect(results[0].message, contains('refused the API key ABC123DEF4'));
    expect(results[1].message, contains('may not read the certificates'));
    expect(results[2].message, contains('could not read the certificates'));
  });
}
