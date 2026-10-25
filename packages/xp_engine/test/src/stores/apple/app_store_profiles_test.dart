import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/credential_harness.dart';

void main() {
  late InMemoryCredentialRepository credentials;
  late BytesSecretStore secrets;
  late FakeAppStoreConnect asc;
  late AscKey? connectedWith;
  late AppStoreProfiles profiles;
  final key = AppStoreProfiles.keyFor('identity', 'com.mataa.app');

  Future<void> assign(CredentialKind kind, String secretKey) async {
    await credentials.put(
      AssignedCredential(
        flavor: testFlavor,
        credential: CredentialRecord(
          id: 'crd_$secretKey',
          name: secretKey,
          kind: kind,
          secretKey: secretKey,
        ),
      ),
    );
    await CredentialMaterial.fromFields(
      kind,
      credentialFields(kind),
    ).write(secrets, secretKey);
  }

  setUp(() async {
    credentials = InMemoryCredentialRepository([testFlavor]);
    secrets = BytesSecretStore();
    asc = FakeAppStoreConnect()
      ..certificates.add(
        const AscCertificate(id: 'cert-1', serialNumber: '0A1B2C3D4E5F'),
      )
      ..bundleIds['com.mataa.app'] = 'bundle-1';
    connectedWith = null;
    profiles = AppStoreProfiles(
      credentials: credentials,
      secrets: secrets,
      connect: (ascKey) {
        connectedWith = ascKey;
        return asc;
      },
      clock: ManualClock(DateTime.utc(2026, 10, 25)),
    );
    await assign(CredentialKind.appleDistribution, 'identity');
    await assign(CredentialKind.ascKey, 'asc');
  });

  Matcher refusal(String message) => throwsA(
    isA<AppStoreProfileException>().having(
      (error) => error.message,
      'message',
      message,
    ),
  );

  test('names a profile by its identity and bundle id', () {
    expect(key, 'identity.profile:com.mataa.app');
    expect(AppStoreProfiles.isProfileKey(key), isTrue);
    expect(AppStoreProfiles.isProfileKey('identity.certificate'), isFalse);
  });

  test("makes the App Store profile with the flavor's API key", () async {
    final profile = await profiles.profile('prj_1', key);

    expect(
      utf8.decode(profile),
      'profile XPath com.mataa.app A1B2C3D4E5F bundle-1 cert-1',
    );
    expect(connectedWith?.keyId, 'ABC123DEF4');
    expect(asc.calls, [
      'distributionCertificates',
      'appStoreProfiles XPath com.mataa.app A1B2C3D4E5F',
      'bundleIdOf com.mataa.app',
      'createAppStoreProfile XPath com.mataa.app A1B2C3D4E5F bundle-1 cert-1',
    ]);
  });

  test('reuses the profile it made until a day before it expires', () async {
    final first = await profiles.profile('prj_1', key);
    final again = await profiles.profile('prj_1', key);

    expect(again, first);
    expect(asc.profiles, hasLength(1));
    expect(
      asc.calls.where((call) => call.startsWith('createAppStoreProfile')),
      hasLength(1),
    );
  });

  test('makes it again when it expires within a day, deleting the old one '
      'first: names are unique in the team', () async {
    asc.profileExpiry = DateTime.utc(2026, 10, 25, 12);
    await profiles.profile('prj_1', key);
    asc
      ..profileExpiry = DateTime.utc(2027)
      ..calls.clear();

    final renewed = await profiles.profile('prj_1', key);

    expect(utf8.decode(renewed), startsWith('profile XPath'));
    expect(asc.calls, [
      'distributionCertificates',
      'appStoreProfiles XPath com.mataa.app A1B2C3D4E5F',
      'deleteProfile profile-4',
      'bundleIdOf com.mataa.app',
      'createAppStoreProfile XPath com.mataa.app A1B2C3D4E5F bundle-1 cert-1',
    ]);
    expect(asc.profiles.single.expirationDate, DateTime.utc(2027));
  });

  test('refuses a saved App Store Connect key that is not one', () async {
    await secrets.write('asc', 'not json');

    await expectLater(
      profiles.profile('prj_1', key),
      throwsA(
        isA<AppStoreProfileException>().having(
          (e) => e.message,
          'message',
          startsWith('The App Store Connect key of the flavor prod cannot be'),
        ),
      ),
    );
  });

  test('refuses a saved certificate that is not one', () async {
    await secrets.writeBytes('identity.certificate', [1, 2, 3]);

    await expectLater(
      profiles.profile('prj_1', key),
      throwsA(
        isA<AppStoreProfileException>().having(
          (e) => e.message,
          'message',
          startsWith('The saved identity of the flavor prod cannot be used'),
        ),
      ),
    );
  });

  test('refuses a key no flavor of the project signs with', () async {
    await expectLater(
      profiles.profile('prj_2', key),
      refusal(
        'No flavor of the project signs com.mataa.app with this '
        'identity.',
      ),
    );
    await expectLater(
      profiles.profile(
        'prj_1',
        AppStoreProfiles.keyFor('identity', 'com.other.app'),
      ),
      refusal(
        'No flavor of the project signs com.other.app with this '
        'identity.',
      ),
    );
  });

  test('needs the API key and the certificate of the flavor', () async {
    await credentials.unassign('flv_1', CredentialKind.ascKey);
    await expectLater(
      profiles.profile('prj_1', key),
      refusal(
        'The flavor prod needs an App Store Connect API key and a saved '
        'identity for the engine to make its profile.',
      ),
    );
    await assign(CredentialKind.ascKey, 'asc');
    secrets.values.remove('identity.certificate');
    await expectLater(
      profiles.profile('prj_1', key),
      throwsA(isA<AppStoreProfileException>()),
    );
    expect(asc.calls, isEmpty);
  });

  test('refuses a certificate App Store Connect no longer lists', () async {
    asc.certificates.clear();

    await expectLater(
      profiles.profile('prj_1', key),
      refusal(
        'App Store Connect lists no distribution certificate with the '
        'serial number A1B2C3D4E5F: it was revoked.',
      ),
    );
  });

  test('refuses a bundle id the team has not registered', () async {
    asc.bundleIds.clear();

    await expectLater(
      profiles.profile('prj_1', key),
      refusal('App Store Connect has no bundle id com.mataa.app registered.'),
    );
  });

  test('says what App Store Connect refused', () async {
    asc.failure = const AscForbiddenException('no role');

    await expectLater(
      profiles.profile('prj_1', key),
      refusal(
        'App Store Connect could not make the profile of com.mataa.app: '
        'no role',
      ),
    );
    expect('${const AppStoreProfileException('x')}', contains('x'));
  });
}
