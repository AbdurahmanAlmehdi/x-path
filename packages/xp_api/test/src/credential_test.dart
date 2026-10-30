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
          'apple_distribution',
          'play_sa',
          'firebase_sa',
          'keystore',
          'dart_defines',
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

    test('carries an optional name, trimmed', () {
      final request = SaveCredentialRequest.fromJson(const {
        'flavor': 'prod',
        'kind': 'shorebird',
        'name': '  Studio Shorebird  ',
        'token': 'sb_api_x',
      });

      expect(request.name, 'Studio Shorebird');
      expect(request.material, {'token': 'sb_api_x'});
      expect(request.toJson()['name'], 'Studio Shorebird');
      expect(SaveCredentialRequest.fromJson(request.toJson()), request);
      expect(
        () => SaveCredentialRequest.fromJson(const {
          'flavor': 'prod',
          'kind': 'shorebird',
          'name': '',
        }),
        throwsFormatException,
      );
    });
  });

  group('credentialName', () {
    test('trims a usable name', () {
      expect(
        credentialName('  Personal Apple Dev Account '),
        'Personal Apple Dev Account',
      );
    });

    test('refuses what cannot name a credential', () {
      for (final name in <Object?>[
        null,
        3,
        '   ',
        'a' * (maxCredentialNameLength + 1),
        'two\nlines',
        'bell\u007f',
      ]) {
        expect(
          () => credentialName(name),
          throwsFormatException,
          reason: '$name',
        );
      }
      expect(credentialName('a' * maxCredentialNameLength), hasLength(80));
    });
  });

  group('CredentialKind labels', () {
    test('name every kind for people', () {
      expect(CredentialKind.ascKey.label, 'App Store Connect API key');
      expect({
        for (final kind in CredentialKind.values) kind.label,
      }, hasLength(CredentialKind.values.length));
    });

    test('every kind but github is named and assigned', () {
      expect(
        [
          for (final kind in CredentialKind.values)
            if (!kind.isNamed) kind,
        ],
        [CredentialKind.github],
      );
    });
  });

  group('Credential of a flavor', () {
    test('carries the name and both checks', () {
      const credential = Credential(
        id: 'crd_1',
        name: 'Personal Apple Dev Account',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.rejected,
        credentialStatus: CredentialStatus.verified,
        assignmentStatus: CredentialStatus.rejected,
      );

      expect(credential.toJson(), {
        'id': 'crd_1',
        'name': 'Personal Apple Dev Account',
        'projectId': 'prj_1',
        'app': '.',
        'flavor': 'prod',
        'kind': 'asc_key',
        'status': 'rejected',
        'credentialStatus': 'verified',
        'assignmentStatus': 'rejected',
      });
      expect(Credential.fromJson(credential.toJson()), credential);
    });
  });

  group('NamedCredential', () {
    final at = DateTime.utc(2026, 10, 18, 9);

    test('round-trips through JSON with its usages', () {
      final credential = NamedCredential(
        id: 'crd_1',
        name: 'Personal Apple Dev Account',
        kind: CredentialKind.ascKey,
        status: CredentialStatus.verified,
        account: 'ABC123DEF4',
        verifiedAt: at,
        checkedAt: at,
        usedBy: [
          CredentialUsage(
            projectId: 'prj_1',
            project: 'acme/shop',
            app: '.',
            flavor: 'prod',
            status: CredentialStatus.rejected,
            verifiedAt: at,
            checkedAt: at,
            message: 'No app.',
            fix: 'Create it.',
          ),
        ],
      );

      final json = credential.toJson();
      expect(json['usedBy'], [
        {
          'projectId': 'prj_1',
          'project': 'acme/shop',
          'app': '.',
          'flavor': 'prod',
          'status': 'rejected',
          'verifiedAt': '2026-10-18T09:00:00.000Z',
          'checkedAt': '2026-10-18T09:00:00.000Z',
          'message': 'No app.',
          'fix': 'Create it.',
        },
      ]);
      expect(NamedCredential.fromJson(json), credential);
      final response = NamedCredentialsResponse([credential]);
      expect(NamedCredentialsResponse.fromJson(response.toJson()), response);
    });

    test('reads a credential without usages and leaves out the absent', () {
      const credential = NamedCredential(
        id: 'crd_2',
        name: 'Slack',
        kind: CredentialKind.slack,
        status: CredentialStatus.unverified,
        message: 'm',
        fix: 'f',
      );

      expect(
        NamedCredential.fromJson(const {
          'id': 'crd_2',
          'name': 'Slack',
          'kind': 'slack',
          'status': 'unverified',
          'message': 'm',
          'fix': 'f',
        }),
        credential,
      );
      expect(credential.toJson().keys, [
        'id',
        'name',
        'kind',
        'status',
        'message',
        'fix',
        'usedBy',
      ]);
    });
  });

  group('CreateCredentialRequest', () {
    test('splits the name and kind from the material', () {
      final request = CreateCredentialRequest.fromJson(const {
        'name': ' Mataa Apple Dev Account ',
        'kind': 'apple_id',
        'appleId': 'dev@example.com',
        'password': 'abcd-efgh-ijkl-mnop',
      });

      expect(request.name, 'Mataa Apple Dev Account');
      expect(request.kind, CredentialKind.appleId);
      expect(request.material, {
        'appleId': 'dev@example.com',
        'password': 'abcd-efgh-ijkl-mnop',
      });
      expect(CreateCredentialRequest.fromJson(request.toJson()), request);
      expect(
        request.toString(),
        'CreateCredentialRequest(Mataa Apple Dev Account, apple_id)',
      );
    });

    test('refuses a request without a usable name or kind', () {
      for (final json in <Map<String, dynamic>>[
        {'kind': 'slack'},
        {'name': ' ', 'kind': 'slack'},
        {'name': 'n'},
        {'name': 'n', 'kind': 'dropbox'},
      ]) {
        expect(
          () => CreateCredentialRequest.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });

  group('ReplaceCredentialRequest', () {
    test('keeps the secret fields and drops the kind', () {
      final request = ReplaceCredentialRequest.fromJson(const {
        'kind': 'shorebird',
        'token': 'sb_api_secret',
      });

      expect(request.material, {'token': 'sb_api_secret'});
      expect(request.toJson(), {'token': 'sb_api_secret'});
      expect(ReplaceCredentialRequest.fromJson(request.toJson()), request);
      expect(request.toString(), 'ReplaceCredentialRequest(token)');
    });
  });

  group('RenameCredentialRequest', () {
    test('reads a usable name', () {
      final request = RenameCredentialRequest.fromJson(const {'name': ' New '});

      expect(request.name, 'New');
      expect(request.toJson(), {'name': 'New'});
      expect(RenameCredentialRequest.fromJson(request.toJson()), request);
      expect(
        () => RenameCredentialRequest.fromJson(const {}),
        throwsFormatException,
      );
    });
  });

  group('CreateDistributionCertificateRequest', () {
    test('reads a usable name', () {
      final request = CreateDistributionCertificateRequest.fromJson(const {
        'name': ' Linux signing ',
      });

      expect(request.name, 'Linux signing');
      expect(request.toJson(), {'name': 'Linux signing'});
      expect(
        CreateDistributionCertificateRequest.fromJson(request.toJson()),
        request,
      );
      expect(
        () => CreateDistributionCertificateRequest.fromJson(const {}),
        throwsFormatException,
      );
    });
  });

  group('AssignCredentialRequest', () {
    test('defaults to this flavor only, without replacing', () {
      final request = AssignCredentialRequest.fromJson(const {
        'credentialId': 'crd_1',
      });

      expect(request.allFlavors, isFalse);
      expect(request.replace, isFalse);
      const every = AssignCredentialRequest(
        credentialId: 'crd_1',
        allFlavors: true,
        replace: true,
      );
      expect(every.toJson(), {
        'credentialId': 'crd_1',
        'allFlavors': true,
        'replace': true,
      });
      expect(AssignCredentialRequest.fromJson(every.toJson()), every);
    });
  });

  group('AssignCredentialResponse', () {
    test('round-trips the assigned and the kept flavors', () {
      const response = AssignCredentialResponse(
        assigned: [
          Credential(
            id: 'crd_1',
            projectId: 'prj_1',
            app: '.',
            flavor: 'dev',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.verified,
          ),
        ],
        kept: [
          Credential(
            id: 'crd_2',
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.verified,
          ),
        ],
      );

      expect(AssignCredentialResponse.fromJson(response.toJson()), response);
      expect(
        AssignCredentialResponse.fromJson(const {'assigned': <Object>[]}).kept,
        isEmpty,
      );
    });
  });
}
