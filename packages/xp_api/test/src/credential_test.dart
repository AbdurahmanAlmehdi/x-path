import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('CredentialKind', () {
    test('uses the kinds of the credential_ref table on the wire', () {
      expect(
        [for (final kind in CredentialKind.values) kind.wire],
        [
          'asc_key',
          'apple_id',
          'play_sa',
          'firebase_sa',
          'keystore',
          'shorebird',
          'github',
          'slack',
        ],
      );
    });

    test('is found by its wire name', () {
      expect(CredentialKind.fromWire('firebase_sa'), CredentialKind.firebaseSa);
      expect(CredentialKind.fromWire('ascKey'), isNull);
    });
  });

  group('Credential', () {
    final checked = DateTime.utc(2026, 10, 13, 9);

    test('round-trips through JSON and leaves out what is absent', () {
      final credential = Credential(
        id: 'crd_1',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.rejected,
        account: 'ABC123DEF4',
        verifiedAt: checked,
        checkedAt: checked,
        message: 'Revoked.',
        fix: 'Create a new key.',
      );

      expect(credential.toJson(), {
        'id': 'crd_1',
        'projectId': 'prj_1',
        'app': '.',
        'flavor': 'prod',
        'kind': 'asc_key',
        'status': 'rejected',
        'account': 'ABC123DEF4',
        'verifiedAt': '2026-10-13T09:00:00.000Z',
        'checkedAt': '2026-10-13T09:00:00.000Z',
        'message': 'Revoked.',
        'fix': 'Create a new key.',
      });
      expect(Credential.fromJson(credential.toJson()), credential);
      expect(
        const Credential(
          id: 'crd_2',
          projectId: 'prj_1',
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.slack,
          status: CredentialStatus.unverified,
        ).toJson().keys,
        ['id', 'projectId', 'app', 'flavor', 'kind', 'status'],
      );
    });

    test('lists credentials in a response', () {
      const response = CredentialsResponse([
        Credential(
          id: 'crd_1',
          projectId: 'prj_1',
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.github,
          status: CredentialStatus.verified,
        ),
      ]);

      expect(CredentialsResponse.fromJson(response.toJson()), response);
    });
  });

  group('SaveCredentialRequest', () {
    test('splits the selectors from the material', () {
      final request = SaveCredentialRequest.fromJson(const {
        'app': 'apps/customer',
        'flavor': 'prod',
        'kind': 'apple_id',
        'appleId': 'dev@example.com',
        'password': 'abcd-efgh-ijkl-mnop',
      });

      expect(request.app, 'apps/customer');
      expect(request.flavor, 'prod');
      expect(request.kind, CredentialKind.appleId);
      expect(request.material, {
        'appleId': 'dev@example.com',
        'password': 'abcd-efgh-ijkl-mnop',
      });
      expect(SaveCredentialRequest.fromJson(request.toJson()), request);
    });

    test('defaults the app to the root', () {
      final request = SaveCredentialRequest.fromJson(const {
        'flavor': 'default',
        'kind': 'github',
        'token': 'ghp_x',
      });

      expect(request.app, '.');
    });

    test('never shows the material when printed', () {
      final request = SaveCredentialRequest.fromJson(const {
        'flavor': 'prod',
        'kind': 'github',
        'token': 'ghp_secret',
      });

      expect(request.toString(), 'SaveCredentialRequest(., prod, github)');
    });

    test('refuses a request without a usable app, flavor or kind', () {
      const base = {'flavor': 'prod', 'kind': 'github'};
      for (final json in <Map<String, dynamic>>[
        {...base, 'app': ''},
        {...base, 'app': 3},
        {...base, 'flavor': ''},
        {'kind': 'github'},
        {...base, 'kind': 'dropbox'},
        {'flavor': 'prod'},
        {...base, 'kind': 7},
      ]) {
        expect(
          () => SaveCredentialRequest.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });
}
