import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/credential_harness.dart';
import '../../../../helpers/guard_harness.dart';

AssignedCredential _record(
  CredentialKind kind,
  CredentialStatus status, {
  String? message,
  String? fix,
  CredentialStatus assignment = CredentialStatus.verified,
  String? assignmentMessage,
  String? assignmentFix,
  CredentialFlavor flavor = testFlavor,
}) => AssignedCredential(
  flavor: flavor,
  credential: CredentialRecord(
    id: 'crd_${kind.wire}_${flavor.name}',
    name: '${kind.label} ${flavor.name}',
    kind: kind,
    secretKey: 'credential.${kind.wire}',
    check: CredentialCheck(status: status, message: message, fix: fix),
  ),
  check: CredentialCheck(
    status: assignment,
    message: assignmentMessage,
    fix: assignmentFix,
  ),
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

  test('passes when every credential and assignment was accepted', () async {
    await repository.put(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );
    await repository.put(
      _record(CredentialKind.slack, CredentialStatus.verified),
    );

    final result = await run();

    expect(result.status, GuardStatus.passed);
    expect(result.message, '2 credentials accepted at the last check.');
  });

  test('says "credential" for one', () async {
    await repository.put(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );

    expect((await run()).message, '1 credential accepted at the last check.');
  });

  test('fails with the reason and the fix of a refused credential', () async {
    await repository.put(
      _record(
        CredentialKind.ascKey,
        CredentialStatus.rejected,
        message: 'App Store Connect refused the API key ABC123DEF4.',
        fix: 'Create a new key.',
      ),
    );

    final result = await run();

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      contains(
        'asc_key "App Store Connect API key prod": App Store Connect refused',
      ),
    );
    expect(result.fix, 'asc_key: Create a new key.');
  });

  test("fails when the credential cannot reach the flavor's app", () async {
    await repository.put(
      _record(
        CredentialKind.playSa,
        CredentialStatus.verified,
        assignment: CredentialStatus.rejected,
        assignmentMessage: 'Google Play does not know com.mataa.app.',
        assignmentFix: 'Invite the service account.',
      ),
    );

    final result = await run();

    expect(result.status, GuardStatus.failed);
    expect(result.message, contains('Google Play does not know'));
    expect(result.fix, 'play_sa: Invite the service account.');
  });

  test('fails for a refusal that came without a reason', () async {
    await repository.put(
      _record(CredentialKind.appleId, CredentialStatus.rejected),
    );

    final result = await run();

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      'apple_id "Apple ID prod": refused at the last check.',
    );
    expect(result.fix, '');
  });

  test('only looks at the kinds the job needs', () async {
    await repository.put(
      _record(CredentialKind.slack, CredentialStatus.rejected, message: 'x'),
    );
    await repository.put(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );

    final result = await run(kinds: [CredentialKind.ascKey]);

    expect(result.status, GuardStatus.passed);
  });

  test('fails for a needed kind that is not assigned', () async {
    await repository.put(
      _record(CredentialKind.ascKey, CredentialStatus.verified),
    );

    final result = await run(
      kinds: [CredentialKind.ascKey, CredentialKind.firebaseSa],
    );

    expect(result.status, GuardStatus.failed);
    expect(
      result.message,
      'firebase_sa: no credential is assigned to the flavor.',
    );
    expect(result.fix, contains('Assign a credential of firebase_sa'));
    expect(result.fix, contains('xp credentials assign'));
  });

  test('warns, and does not stop the job, when it could not check', () async {
    await repository.put(
      _record(CredentialKind.ascKey, CredentialStatus.unreachable),
    );
    await repository.put(
      _record(
        CredentialKind.slack,
        CredentialStatus.verified,
        assignment: CredentialStatus.unverified,
      ),
    );

    final result = await run();

    expect(result.status, GuardStatus.warned);
    expect(
      result.message,
      'Not confirmed: asc_key "App Store Connect API key prod" (could not be '
      'reached), slack "Slack webhook prod" (never checked).',
    );
    expect(result.fix, contains('xp credentials verify'));
  });

  test('only looks at the credentials of its own flavor', () async {
    const dev = CredentialFlavor(
      id: 'flv_2',
      projectId: 'prj_1',
      appPath: '.',
      name: 'dev',
    );
    repository.flavors.add(dev);
    await repository.put(
      _record(
        CredentialKind.ascKey,
        CredentialStatus.rejected,
        message: 'x',
        flavor: dev,
      ),
    );

    expect((await run()).status, GuardStatus.skipped);
  });
}
