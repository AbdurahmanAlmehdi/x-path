import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/credential_harness.dart';
import '../../../../helpers/guard_harness.dart';

CredentialRecord _record(
  CredentialKind kind,
  CredentialStatus status, {
  String? message,
  String? fix,
}) => CredentialRecord(
  id: 'crd_${kind.wire}',
  flavor: testFlavor,
  kind: kind,
  secretKey: 'credential.${kind.wire}',
  status: status,
  message: message,
  fix: fix,
);

void main() {
  late InMemoryCredentialRepository repository;

  setUp(() => repository = InMemoryCredentialRepository([testFlavor]));

  Future<GuardCheckResult> run({
    String? flavorId = 'flv_1',
    List<CredentialKind> kinds = const [],
  }) => CredentialsCheck(repository)
      .run(guardRequest(flavorId: flavorId, credentialKinds: kinds).request);

  test('is the credentials check', () {
    expect(CredentialsCheck(repository).name, GuardCheckName.credentials);
  });

  test('is skipped for a job without a flavor', () async {
    final result = await run(flavorId: null);

    expect(result.status, GuardStatus.skipped);
  });

  test('is skipped for a flavor without credentials', () async {
    final result = await run();

    expect(result.status, GuardStatus.skipped);
    expect(result.message, contains('needs no credentials'));
  });

  test('passes when every credential was accepted', () async {
    await repository.save(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );
    await repository.save(
      _record(CredentialKind.slack, CredentialStatus.verified),
    );

    final result = await run();

    expect(result.status, GuardStatus.passed);
    expect(result.message, '2 credentials accepted at the last check.');
  });

  test('says "credential" for one', () async {
    await repository.save(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );

    expect((await run()).message, '1 credential accepted at the last check.');
  });

  test('fails with the reason and the fix of a refused credential', () async {
    await repository.save(
      _record(
        CredentialKind.ascKey,
        CredentialStatus.rejected,
        message: 'App Store Connect refused the API key ABC123DEF4.',
        fix: 'Create a new key.',
      ),
    );

    final result = await run();

    expect(result.status, GuardStatus.failed);
    expect(result.message, contains('asc_key: App Store Connect refused'));
    expect(result.fix, 'asc_key: Create a new key.');
  });

  test('fails for a refusal that came without a reason', () async {
    await repository.save(
      _record(CredentialKind.appleId, CredentialStatus.rejected),
    );

    final result = await run();

    expect(result.status, GuardStatus.failed);
    expect(result.message, 'apple_id: refused at the last check.');
    expect(result.fix, '');
  });

  test('only looks at the kinds the job needs', () async {
    await repository.save(
      _record(CredentialKind.slack, CredentialStatus.rejected, message: 'x'),
    );
    await repository.save(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );

    final result = await run(kinds: [CredentialKind.ascKey]);

    expect(result.status, GuardStatus.passed);
  });

  test('fails for a needed kind that is not saved', () async {
    await repository.save(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );

    final result = await run(
      kinds: [CredentialKind.ascKey, CredentialKind.firebaseSa],
    );

    expect(result.status, GuardStatus.failed);
    expect(result.message, 'firebase_sa: no credential is saved.');
    expect(result.fix, contains('Save firebase_sa'));
  });

  test('warns, and does not stop the job, when it could not check', () async {
    await repository.save(
      _record(CredentialKind.ascKey, CredentialStatus.unreachable),
    );
    await repository.save(
      _record(CredentialKind.slack, CredentialStatus.unverified),
    );

    final result = await run();

    expect(result.status, GuardStatus.warned);
    expect(
      result.message,
      'Not confirmed: asc_key (could not be reached), slack (never checked).',
    );
  });

  test('only looks at the credentials of its own flavor', () async {
    repository.flavors.add(
      const CredentialFlavor(
        id: 'flv_2',
        projectId: 'prj_1',
        appPath: '.',
        name: 'dev',
      ),
    );
    await repository.save(
      CredentialRecord(
        id: 'crd_other',
        flavor: repository.flavors.last,
        kind: CredentialKind.ascKey,
        secretKey: 'k',
        status: CredentialStatus.rejected,
        message: 'x',
      ),
    );

    expect((await run()).status, GuardStatus.skipped);
  });
}
