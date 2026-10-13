import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';

void main() {
  final at = DateTime.utc(2026, 10, 13, 9);
  final later = DateTime.utc(2026, 10, 14, 9);
  const record = CredentialRecord(
    id: 'crd_1',
    flavor: testFlavor,
    kind: CredentialKind.ascKey,
    secretKey: 'credential.crd_1',
  );

  test('compare by value', () {
    expect(
      record,
      const CredentialRecord(
        id: 'crd_1',
        flavor: testFlavor,
        kind: CredentialKind.ascKey,
        secretKey: 'credential.crd_1',
      ),
    );
    expect(
      record,
      isNot(record.checked(status: CredentialStatus.verified, at: at)),
    );
    expect(
      testFlavor,
      isNot(
        const CredentialFlavor(
          id: 'flv_1',
          projectId: 'prj_1',
          appPath: '.',
          name: 'dev',
        ),
      ),
    );
  });

  test('starts unchecked', () {
    expect(record.status, CredentialStatus.unverified);
    expect(record.checkedAt, isNull);
    expect(record.verifiedAt, isNull);
  });

  test('a check that accepts sets both times and clears the complaint', () {
    final refused = record.checked(
      status: CredentialStatus.rejected,
      at: at,
      message: 'Revoked.',
      fix: 'Replace it.',
    );
    final accepted = refused.checked(
      status: CredentialStatus.verified,
      at: later,
      account: 'KEY1',
    );

    expect(accepted.status, CredentialStatus.verified);
    expect(accepted.verifiedAt, later);
    expect(accepted.checkedAt, later);
    expect(accepted.account, 'KEY1');
    expect(accepted.message, isNull);
    expect(accepted.fix, isNull);
  });

  test('a check that refuses keeps the time of the last acceptance', () {
    final accepted = record.checked(
      status: CredentialStatus.verified,
      at: at,
      account: 'KEY1',
    );
    final refused = accepted.checked(
      status: CredentialStatus.rejected,
      at: later,
      message: 'Revoked.',
      fix: 'Replace it.',
    );

    expect(refused.verifiedAt, at);
    expect(refused.checkedAt, later);
    expect(refused.account, 'KEY1');
    expect(refused.message, 'Revoked.');
  });

  test('has an API form with the names of the app and the flavor', () {
    final api = record
        .checked(status: CredentialStatus.verified, at: at, account: 'KEY1')
        .toApi();

    expect(api.projectId, 'prj_1');
    expect(api.app, '.');
    expect(api.flavor, 'prod');
    expect(api.kind, CredentialKind.ascKey);
    expect(api.status, CredentialStatus.verified);
    expect(api.account, 'KEY1');
    expect(api.verifiedAt, at);
    expect(api.toJson().toString(), isNot(contains('secret')));
  });
}
