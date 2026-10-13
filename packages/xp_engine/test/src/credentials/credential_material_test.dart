import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';

CredentialMaterial _read(CredentialKind kind, [Map<String, dynamic>? over]) =>
    CredentialMaterial.fromFields(kind, {...credentialFields(kind), ...?over});

void main() {
  group('fromFields', () {
    test('reads an ASC key, a team key unless told otherwise', () {
      final material = _read(CredentialKind.ascKey) as AscKeyMaterial;

      expect(material.key.keyId, 'ABC123DEF4');
      expect(material.key.kind, AscKeyKind.team);
      expect(material.account, 'ABC123DEF4');
      expect(material.kind, CredentialKind.ascKey);

      final individual = _read(CredentialKind.ascKey, {
        'keyKind': 'individual',
      }) as AscKeyMaterial;
      expect(individual.key.kind, AscKeyKind.individual);
    });

    test('reads an Apple ID', () {
      final material = _read(CredentialKind.appleId) as AppleIdMaterial;

      expect(material.appleId, 'dev@example.com');
      expect(material.account, 'dev@example.com');
      expect(material.secretValues, ['abcd-efgh-ijkl-mnop']);
      expect(material.kind, CredentialKind.appleId);
    });

    test('reads a service account for Play and for Firebase', () {
      for (final kind in [CredentialKind.playSa, CredentialKind.firebaseSa]) {
        final material = _read(kind) as ServiceAccountMaterial;

        expect(material.kind, kind);
        expect(material.account, testServiceAccount.clientEmail);
        expect(material.secretValues, contains(testServiceAccount.privateKey));
      }
    });

    test('reads a keystore, the key password defaulting to the store one', () {
      final material = _read(CredentialKind.keystore) as KeystoreMaterial;

      expect(material.bytes, [1, 2, 3, 4, 250]);
      expect(material.alias, 'upload');
      expect(material.keyPassword, 'store-pass');
      expect(material.account, 'upload');
      expect(material.kind, CredentialKind.keystore);
      expect(material.secretValues, ['store-pass', 'store-pass']);

      final other = _read(CredentialKind.keystore, {
        'keyPassword': 'key-pass',
      }) as KeystoreMaterial;
      expect(other.keyPassword, 'key-pass');
    });

    test('reads base64 with line breaks and without padding', () {
      final material = _read(CredentialKind.keystore, {
        'keystore': 'AQID\nBPo',
      }) as KeystoreMaterial;

      expect(material.bytes, [1, 2, 3, 4, 250]);
    });

    test('reads tokens and a webhook', () {
      final shorebird = _read(CredentialKind.shorebird, {
        'token': ' sb_api_x \n',
      }) as TokenMaterial;
      final github = _read(CredentialKind.github) as TokenMaterial;
      final slack = _read(CredentialKind.slack) as SlackMaterial;

      expect(shorebird.token, 'sb_api_x');
      expect(shorebird.kind, CredentialKind.shorebird);
      expect(github.kind, CredentialKind.github);
      expect(github.account, isNull);
      expect(slack.webhookUrl, startsWith('https://hooks.slack.com/'));
      expect(slack.account, isNull);
      expect(slack.kind, CredentialKind.slack);
    });

    test('says which field is missing or wrong, without a value', () {
      for (final (kind, over) in <(CredentialKind, Map<String, dynamic>)>[
        (CredentialKind.ascKey, {'keyId': ''}),
        (CredentialKind.ascKey, {'privateKey': 4}),
        (CredentialKind.ascKey, {'keyKind': 'robot'}),
        (CredentialKind.ascKey, {'keyKind': ''}),
        (CredentialKind.appleId, {'password': null}),
        (CredentialKind.playSa, {'serviceAccount': null}),
        (CredentialKind.keystore, {'storePassword': ' '}),
        (CredentialKind.keystore, {'keyPassword': 5}),
        (CredentialKind.shorebird, {'token': null}),
        (CredentialKind.slack, {'webhookUrl': ''}),
      ]) {
        expect(
          () => _read(kind, over),
          throwsA(isA<CredentialRequestException>()),
          reason: '$kind $over',
        );
      }
    });

    test('refuses a service account file that is not one', () {
      for (final text in ['nope', '[]', '{"type": "user"}', '{}']) {
        expect(
          () => _read(CredentialKind.firebaseSa, {'serviceAccount': text}),
          throwsA(
            isA<CredentialRejectedException>().having(
              (e) => e.fix,
              'fix',
              contains('JSON key file'),
            ),
          ),
          reason: text,
        );
      }
    });

    test('refuses a keystore that is not base64 or is empty', () {
      expect(
        () => _read(CredentialKind.keystore, {'keystore': '***'}),
        throwsA(isA<CredentialRejectedException>()),
      );
      expect(
        () => _read(CredentialKind.keystore, {'keystore': '=='}),
        throwsA(isA<CredentialRejectedException>()),
      );
    });
  });

  group('storage', () {
    late BytesSecretStore secrets;

    setUp(() => secrets = BytesSecretStore());

    Future<CredentialMaterial?> roundTrip(
      CredentialKind kind, {
      String key = 'credential.crd_1',
    }) async {
      final material = _read(kind);
      await material.write(secrets, key);
      return await CredentialMaterial.load(
        kind,
        key,
        material.account,
        secrets,
      );
    }

    test('an ASC key is the JSON of AscKey', () async {
      final loaded = await roundTrip(CredentialKind.ascKey);

      expect(loaded, isA<AscKeyMaterial>());
      expect(
        AscKey.fromSecret(secrets.text('credential.crd_1')!).keyId,
        'ABC123DEF4',
      );
    });

    test('an Apple ID password is stored as it is', () async {
      final loaded = await roundTrip(CredentialKind.appleId);

      expect(secrets.text('credential.crd_1'), 'abcd-efgh-ijkl-mnop');
      expect((loaded! as AppleIdMaterial).appleId, 'dev@example.com');
    });

    test('a service account is the key file, as it is', () async {
      final fields = credentialFields(CredentialKind.playSa);
      final loaded = await roundTrip(CredentialKind.playSa);

      expect(secrets.text('credential.crd_1'), fields['serviceAccount']);
      expect(loaded, isA<ServiceAccountMaterial>());
      expect(
        (await roundTrip(CredentialKind.firebaseSa))!.kind,
        CredentialKind.firebaseSa,
      );
    });

    test('a keystore is bytes with two passwords beside it', () async {
      final loaded =
          (await roundTrip(CredentialKind.keystore))! as KeystoreMaterial;

      expect(secrets.values['credential.crd_1'], [1, 2, 3, 4, 250]);
      expect(secrets.text('credential.crd_1.storePassword'), 'store-pass');
      expect(secrets.text('credential.crd_1.keyPassword'), 'store-pass');
      expect(loaded.bytes, [1, 2, 3, 4, 250]);
      expect(loaded.alias, 'upload');
    });

    test('tokens and webhooks are stored as they are', () async {
      expect(await roundTrip(CredentialKind.shorebird), isA<TokenMaterial>());
      expect(secrets.text('credential.crd_1'), 'sb_api_abc123');
      expect(await roundTrip(CredentialKind.github), isA<TokenMaterial>());
      expect(await roundTrip(CredentialKind.slack), isA<SlackMaterial>());
    });

    test('load finds nothing when a part is missing', () async {
      for (final kind in CredentialKind.values) {
        expect(
          await CredentialMaterial.load(kind, 'nothing', 'x', secrets),
          isNull,
          reason: '$kind',
        );
      }
      await _read(CredentialKind.appleId).write(secrets, 'k');
      expect(
        await CredentialMaterial.load(
          CredentialKind.appleId,
          'k',
          null,
          secrets,
        ),
        isNull,
      );
      await _read(CredentialKind.keystore).write(secrets, 'ks');
      expect(
        await CredentialMaterial.load(
          CredentialKind.keystore,
          'ks',
          null,
          secrets,
        ),
        isNull,
      );
      secrets.values.remove('ks.keyPassword');
      expect(
        await CredentialMaterial.load(
          CredentialKind.keystore,
          'ks',
          'a',
          secrets,
        ),
        isNull,
      );
    });

    test('load rejects a stored secret that is not usable', () async {
      secrets.values['k'] = utf8.encode('not json');

      await expectLater(
        CredentialMaterial.load(CredentialKind.ascKey, 'k', null, secrets),
        throwsFormatException,
      );
      await expectLater(
        CredentialMaterial.load(CredentialKind.playSa, 'k', null, secrets),
        throwsFormatException,
      );
    });

    test('erase removes the secret and the extras of a keystore', () async {
      await _read(CredentialKind.keystore).write(secrets, 'ks');
      await _read(CredentialKind.github).write(secrets, 'gh');

      await CredentialMaterial.erase(CredentialKind.keystore, 'ks', secrets);
      await CredentialMaterial.erase(CredentialKind.github, 'gh', secrets);

      expect(secrets.values, isEmpty);
    });
  });

  test('the material of every kind names its secrets for the masker', () {
    for (final kind in CredentialKind.values) {
      expect(_read(kind).secretValues, isNotEmpty, reason: '$kind');
    }
  });
}
