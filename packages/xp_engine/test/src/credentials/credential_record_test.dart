import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';

void main() {
  final morning = DateTime.utc(2026, 10, 13, 9);
  final noon = DateTime.utc(2026, 10, 13, 12);

  const record = CredentialRecord(
    id: 'crd_1',
    name: 'Personal Apple Dev Account',
    kind: CredentialKind.ascKey,
    secretKey: 'credential.crd_1',
  );

  group('CredentialFlavor', () {
    test('compares by value', () {
      expect(testFlavor, testFlavor);
      expect(testFlavor.props, [
        'flv_1',
        'prj_1',
        null,
        '.',
        'prod',
        'com.mataa.app',
        'com.mataa.app',
      ]);
    });
  });

  group('CredentialCheck', () {
    test('starts never checked', () {
      const check = CredentialCheck();

      expect(check.status, CredentialStatus.unverified);
      expect(check.verifiedAt, isNull);
      expect(check.checkedAt, isNull);
    });

    test('an acceptance sets both times and clears the complaint', () {
      const refused = CredentialCheck(
        status: CredentialStatus.rejected,
        message: 'm',
        fix: 'f',
      );

      final check = refused.after(
        status: CredentialStatus.verified,
        at: morning,
      );

      expect(
        check,
        CredentialCheck(
          status: CredentialStatus.verified,
          verifiedAt: morning,
          checkedAt: morning,
        ),
      );
    });

    test('a refusal keeps the time of the last acceptance', () {
      final check = const CredentialCheck()
          .after(status: CredentialStatus.verified, at: morning)
          .after(
            status: CredentialStatus.rejected,
            at: noon,
            message: 'Expired.',
            fix: 'Replace it.',
          );

      expect(check.verifiedAt, morning);
      expect(check.checkedAt, noon);
      expect(check.message, 'Expired.');
      expect(check.fix, 'Replace it.');
    });
  });

  group('CredentialRecord', () {
    test('compares by value and starts unchecked', () {
      expect(record, record.renamed(record.name));
      expect(record.status, CredentialStatus.unverified);
      expect(record.renamed('Other'), isNot(record));
    });

    test('keeps the account a check found, or the one it had', () {
      final checked = record.checked(
        status: CredentialStatus.verified,
        at: morning,
        account: 'ABC123DEF4',
      );

      expect(checked.account, 'ABC123DEF4');
      expect(
        checked.checked(status: CredentialStatus.rejected, at: noon).account,
        'ABC123DEF4',
      );
    });

    test('a new name keeps everything else', () {
      final checked = record.checked(
        status: CredentialStatus.verified,
        at: morning,
        account: 'A',
      );

      final renamed = checked.renamed('Mataa Apple Dev Account');

      expect(renamed.name, 'Mataa Apple Dev Account');
      expect(renamed.id, checked.id);
      expect(renamed.secretKey, checked.secretKey);
      expect(renamed.account, 'A');
      expect(renamed.check, checked.check);
    });

    test('has an API form with the flavors that use it', () {
      final checked = record.checked(
        status: CredentialStatus.verified,
        at: morning,
        account: 'ABC123DEF4',
      );
      final usage = AssignedCredential(
        flavor: testFlavor.copyWithProjectName('acme/shop'),
        credential: checked,
        check: CredentialCheck(
          status: CredentialStatus.rejected,
          checkedAt: noon,
          message: 'No app.',
          fix: 'Create it.',
        ),
      );

      expect(
        checked.toApi([usage]),
        NamedCredential(
          id: 'crd_1',
          name: 'Personal Apple Dev Account',
          kind: CredentialKind.ascKey,
          status: CredentialStatus.verified,
          account: 'ABC123DEF4',
          verifiedAt: morning,
          checkedAt: morning,
          usedBy: [
            CredentialUsage(
              projectId: 'prj_1',
              project: 'acme/shop',
              app: '.',
              flavor: 'prod',
              status: CredentialStatus.rejected,
              checkedAt: noon,
              message: 'No app.',
              fix: 'Create it.',
            ),
          ],
        ),
      );
      expect(record.toApi().usedBy, isEmpty);
    });
  });

  group('AssignedCredential', () {
    AssignedCredential assigned(
      CredentialStatus credential,
      CredentialStatus assignment, {
      String? credentialMessage,
      String? assignmentMessage,
    }) => AssignedCredential(
      flavor: testFlavor,
      credential: CredentialRecord(
        id: 'crd_1',
        name: 'Key',
        kind: CredentialKind.ascKey,
        secretKey: 'k',
        account: 'A',
        check: CredentialCheck(
          status: credential,
          message: credentialMessage,
          fix: credentialMessage == null ? null : 'credential fix',
          checkedAt: morning,
          verifiedAt: morning,
        ),
      ),
      check: CredentialCheck(
        status: assignment,
        message: assignmentMessage,
        fix: assignmentMessage == null ? null : 'assignment fix',
        checkedAt: noon,
        verifiedAt: noon,
      ),
    );

    test('speaks for its credential', () {
      final a = assigned(CredentialStatus.verified, CredentialStatus.verified);

      expect(a.id, 'crd_1');
      expect(a.kind, CredentialKind.ascKey);
      expect(a.secretKey, 'k');
      expect(a.account, 'A');
    });

    test('is refused when either check refused', () {
      for (final (credential, assignment) in [
        (CredentialStatus.rejected, CredentialStatus.verified),
        (CredentialStatus.verified, CredentialStatus.rejected),
        (CredentialStatus.unreachable, CredentialStatus.rejected),
      ]) {
        expect(
          assigned(credential, assignment).status,
          CredentialStatus.rejected,
        );
      }
    });

    test('is accepted only when both accepted', () {
      expect(
        assigned(CredentialStatus.verified, CredentialStatus.verified).status,
        CredentialStatus.verified,
      );
      expect(
        assigned(
          CredentialStatus.verified,
          CredentialStatus.unreachable,
        ).status,
        CredentialStatus.unreachable,
      );
      expect(
        assigned(CredentialStatus.unverified, CredentialStatus.verified).status,
        CredentialStatus.unverified,
      );
    });

    test("says the credential's complaint first, then its own", () {
      final both = assigned(
        CredentialStatus.rejected,
        CredentialStatus.rejected,
        credentialMessage: 'Revoked.',
        assignmentMessage: 'No app.',
      );
      final own = assigned(
        CredentialStatus.verified,
        CredentialStatus.rejected,
        assignmentMessage: 'No app.',
      );

      expect((both.message, both.fix), ('Revoked.', 'credential fix'));
      expect((own.message, own.fix), ('No app.', 'assignment fix'));
    });

    test('keeps the outcome of a check of the assignment', () {
      final checked = assigned(
        CredentialStatus.verified,
        CredentialStatus.unverified,
      ).checked(status: CredentialStatus.rejected, at: noon, message: 'm');

      expect(checked.check.status, CredentialStatus.rejected);
      expect(checked.check.message, 'm');
      expect(checked.credential.status, CredentialStatus.verified);
    });

    test('takes the newest state of its credential', () {
      final a = assigned(CredentialStatus.verified, CredentialStatus.verified);
      final renamed = a.credential.renamed('New');

      expect(a.withCredential(a.credential), a);
      expect(a.withCredential(renamed), isNot(a));
      expect(a.withCredential(renamed).credential.name, 'New');
      expect(a.withCredential(renamed).check, a.check);
    });

    test('has the API form a flavor sees', () {
      final a = assigned(
        CredentialStatus.verified,
        CredentialStatus.rejected,
        assignmentMessage: 'No app.',
      );

      expect(
        a.toApi(),
        Credential(
          id: 'crd_1',
          name: 'Key',
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          status: CredentialStatus.rejected,
          account: 'A',
          checkedAt: morning,
          message: 'No app.',
          fix: 'assignment fix',
          credentialStatus: CredentialStatus.verified,
          assignmentStatus: CredentialStatus.rejected,
        ),
      );
      expect(
        assigned(
          CredentialStatus.verified,
          CredentialStatus.verified,
        ).toApi().verifiedAt,
        morning,
      );
      expect(
        const AssignedCredential(
          flavor: testFlavor,
          credential: record,
        ).toApi().checkedAt,
        isNull,
      );
    });
  });
}

extension on CredentialFlavor {
  CredentialFlavor copyWithProjectName(String projectName) => CredentialFlavor(
    id: id,
    projectId: projectId,
    projectName: projectName,
    appPath: appPath,
    name: name,
    iosBundleId: iosBundleId,
    androidAppId: androidAppId,
  );
}
