import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/apple_identity_fixtures.dart';
import '../../helpers/approval_harness.dart';
import '../../helpers/credential_harness.dart';
import '../../helpers/job_harness.dart';

class _Keys implements DistributionKeys {
  final names = <String>[];

  @override
  Future<DistributionKey> generate(String commonName) async {
    names.add(commonName);
    return (
      privateKeyPem: testSigningKey,
      csrPem:
          '-----BEGIN CERTIFICATE REQUEST-----\nMIIC\n'
          '-----END CERTIFICATE REQUEST-----\n',
    );
  }
}

void main() {
  final owner = tokenOf(DeviceTokenKind.cli);
  late InMemoryCredentialRepository repository;
  late BytesSecretStore secrets;
  late FakeAppStoreConnect asc;
  late _Keys keys;
  late CredentialService service;
  late DistributionCertificates certificates;

  Future<NamedCredential> create({
    String name = 'Linux signing',
    String flavor = 'prod',
    String app = '.',
    DeviceToken? by,
  }) => certificates.create(
    'prj_1',
    app: app,
    flavor: flavor,
    name: name,
    by: by ?? owner,
  );

  Future<void> giveAscKey() async {
    final key = await service.create(
      CreateCredentialRequest(
        name: 'ASC',
        kind: CredentialKind.ascKey,
        material: credentialFields(CredentialKind.ascKey),
      ),
      by: owner,
    );
    await service.assign(
      'prj_1',
      app: '.',
      flavor: 'prod',
      kind: CredentialKind.ascKey,
      request: AssignCredentialRequest(credentialId: key.id),
      by: owner,
    );
  }

  setUp(() async {
    final clock = ManualClock(DateTime.utc(2026, 10, 25));
    repository = InMemoryCredentialRepository([testFlavor]);
    final projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '1',
        githubRepoId: 1,
        fullName: 'acme/shop',
        remote: 'https://github.com/acme/shop.git',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
    );
    secrets = BytesSecretStore();
    asc = FakeAppStoreConnect()
      ..createdContent = base64.decode(testDistributionCertificate);
    keys = _Keys();
    service = CredentialService(
      repository: repository,
      projects: projects,
      secrets: secrets,
      verifiers: [
        for (final kind in CredentialKind.values) FakeCredentialVerifier(kind),
      ],
      masker: ReplacingMasker(),
      events: InMemoryEventLog(clock: clock),
      clock: clock,
    );
    certificates = DistributionCertificates(
      credentials: service,
      repository: repository,
      secrets: secrets,
      connect: (_) => asc,
      keys: keys,
    );
  });

  test("creates the certificate with the flavor's key, saves the identity "
      'and assigns it to the flavor', () async {
    await giveAscKey();

    final identity = await create();

    expect(identity.kind, CredentialKind.appleDistribution);
    expect(identity.name, 'Linux signing');
    expect(identity.usedBy.single.flavor, 'prod');
    expect(keys.names, ['Linux signing']);
    expect(asc.requests.single, contains('BEGIN CERTIFICATE REQUEST'));
    expect(asc.calls, [
      'distributionCertificates',
      'createDistributionCertificate',
    ]);
    final record = (await repository.get(identity.id))!;
    expect(secrets.text(record.secretKey), testSigningKey);
    expect(
      secrets.values['${record.secretKey}.certificate'],
      base64.decode(testDistributionCertificate),
    );
  });

  test('refuses at the limit, naming the certificates it could '
      'revoke', () async {
    await giveAscKey();
    asc.certificates.addAll([
      AscCertificate(
        id: 'a',
        serialNumber: '0A',
        name: 'Apple Distribution: Acme',
        expirationDate: DateTime.utc(2027, 1, 2),
      ),
      const AscCertificate(id: 'b', serialNumber: '0B'),
      const AscCertificate(id: 'c', serialNumber: '0C'),
    ]);

    await expectLater(
      create(),
      throwsA(
        isA<CertificateLimitException>()
            .having((e) => e.certificates, 'certificates', hasLength(3))
            .having(
              (e) => e.message,
              'message',
              "The team has 3 distribution certificates, Apple's limit is 3: "
                  'Apple Distribution: Acme, serial 0A, expires 2027-01-02; '
                  'a certificate, serial 0B; a certificate, serial 0C.',
            )
            .having((e) => e.fix, 'fix', contains('Revoke one')),
      ),
    );
    expect(keys.names, isEmpty, reason: 'no key is made for nothing');
    expect(await repository.list(), hasLength(1));
  });

  test('needs the flavor, its App Store Connect key and a free name', () async {
    await expectLater(
      create(flavor: 'nope'),
      throwsA(isA<CredentialNotFoundException>()),
    );
    await expectLater(
      create(),
      throwsA(
        isA<CredentialRequestException>().having(
          (e) => e.message,
          'message',
          contains('no App Store Connect API key'),
        ),
      ),
    );
    await giveAscKey();
    await expectLater(
      create(name: 'asc'),
      throwsA(isA<CredentialConflictException>()),
    );
    expect(asc.calls, isEmpty);
  });

  test('only the app and xp create certificates', () async {
    await expectLater(
      create(by: tokenOf(DeviceTokenKind.mcp)),
      throwsA(isA<CredentialForbiddenException>()),
    );
  });

  test('turns what App Store Connect says into a refusal or an '
      'outage', () async {
    await giveAscKey();
    for (final (failure, type) in [
      (const AscAuthException('revoked'), CredentialRejectedException),
      (const AscForbiddenException('role'), CredentialRejectedException),
      (const AscServerException(503, 'down'), CredentialUnreachableException),
    ]) {
      asc.failure = failure;
      await expectLater(
        create(),
        throwsA(predicate((e) => e.runtimeType == type)),
      );
    }
    asc.createdContent = const [];
    await expectLater(
      create(),
      throwsA(
        isA<CredentialUnreachableException>().having(
          (e) => e.message,
          'message',
          contains('sent no content'),
        ),
      ),
    );
  });
}
