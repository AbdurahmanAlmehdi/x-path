import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/credential_harness.dart';
import '../../helpers/guard_harness.dart';
import '../../helpers/job_harness.dart';
import '../../helpers/stub_git.dart';

/// The acceptance test of Phase 10c: an expired ASC key or a revoked
/// app-specific password fails preflight, with a fix hint, before any build
/// step starts.
void main() {
  late ManualClock clock;
  late InMemoryCredentialRepository repository;
  late BytesSecretStore secrets;
  late FakeAppStoreConnect asc;
  late FakeProcessRunner altool;
  late CredentialService credentials;
  late ScriptedStep build;
  late JobRunner runner;

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    repository = InMemoryCredentialRepository([testFlavor]);
    secrets = BytesSecretStore();
    asc = FakeAppStoreConnect();
    asc.apps['com.mataa.app'] = const AscApp(
      id: '1',
      bundleId: 'com.mataa.app',
    );
    altool = FakeProcessRunner(
      (call) => ProcessOutput(
        exitCode: 0,
        stdout: File(
          'test/src/credentials/fixtures/altool_list_providers_ok.txt',
        ).readAsStringSync(),
      ),
    );
    final projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '1',
        githubRepoId: 1,
        fullName: 'o/r',
        remote: 'x',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
    );
    credentials = CredentialService(
      repository: repository,
      projects: projects,
      secrets: secrets,
      verifiers: [
        AscKeyVerifier((_) => asc),
        AppleIdVerifier(runner: altool, isMacOS: true),
      ],
      masker: ReplacingMasker(),
      events: InMemoryEventLog(clock: clock),
      clock: clock,
    );
    build = ScriptedStep(kind: 'build.ios');
    final events = InMemoryEventLog(clock: clock);
    runner = JobRunner(
      jobs: InMemoryJobRepository(),
      steps: StepRegistry([
        GuardStep(
          checks: [CredentialsCheck(repository)],
          git: StubGit(),
          workspaces: (_) => InMemoryWorkspace(customerApp('5.4.1+3283')),
        ),
        build,
      ]),
      supervisor: FakeProcessSupervisor((process) => 0, clock: clock),
      logs: JobLogs(store: InMemoryJobLogStore()),
      secrets: MemorySecretStore(),
      secretFiles: InMemorySecretFileStore(),
      power: NoPowerAssertion(),
      events: events,
      clock: clock,
      hostEnvironment: const {'PATH': '/usr/bin'},
    );
  });

  Future<Job> release() async {
    final guard = GuardStep(
      checks: const [],
      git: StubGit(),
      workspaces: (_) => InMemoryWorkspace({}),
    );
    final input = guardRequest(
      checks: [GuardCheckName.credentials],
      flavorId: 'flv_1',
    ).request.input;
    final job = await runner.create(
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      steps: [
        StepPlan.of(guard, input),
        StepPlan.of(build, <String, dynamic>{}),
      ],
    );
    await runner.start(job.id);
    return await runner.whenFinished(job.id);
  }

  /// Adds a credential of [kind] for the flavor, or replaces its secret.
  Future<void> save(CredentialKind kind) async {
    final owner = tokenOf(DeviceTokenKind.app);
    final assigned = await repository.assignment('flv_1', kind);
    if (assigned != null) {
      await credentials.replace(
        assigned.id,
        ReplaceCredentialRequest(credentialFields(kind)),
        by: owner,
      );
      return;
    }
    final created = await credentials.create(
      CreateCredentialRequest(
        name: kind.label,
        kind: kind,
        material: credentialFields(kind),
      ),
      by: owner,
    );
    await credentials.assign(
      'prj_1',
      app: '.',
      flavor: 'prod',
      kind: kind,
      request: AssignCredentialRequest(credentialId: created.id),
      by: owner,
    );
  }

  test('a job with healthy credentials gets to the build', () async {
    await save(CredentialKind.ascKey);
    await save(CredentialKind.appleId);

    final job = await release();

    expect(job.state, JobState.succeeded);
    expect(build.runs, hasLength(1));
  });

  test('an expired ASC key fails preflight before the build starts', () async {
    await save(CredentialKind.ascKey);
    // Apple revokes the key; the daily health check finds out.
    asc.failure = const AscAuthException('Provided credentials are not valid.');
    clock.advance(const Duration(days: 1));
    await credentials.checkAll();

    final job = await release();

    expect(job.state, JobState.failed);
    expect(job.steps.first.kind, 'guard');
    expect(job.steps.first.state, StepState.failed);
    expect(job.steps.first.message, contains('credentials: asc_key'));
    expect(job.steps.first.message, contains('refused the API key ABC123DEF4'));
    expect(
      job.steps.first.message,
      contains('Create a new key in App Store Connect'),
    );
    expect(job.steps.last.state, StepState.pending);
    expect(build.runs, isEmpty);
  });

  test('a revoked app-specific password fails preflight first', () async {
    await save(CredentialKind.appleId);
    // Apple ID: the user revokes the password at appleid.apple.com.
    altool.handler = (call) => ProcessOutput(
      exitCode: 1,
      stderr: File(
        'test/src/credentials/fixtures/altool_list_providers_bad_password.txt',
      ).readAsStringSync(),
    );
    clock.advance(const Duration(days: 1));
    await credentials.checkAll();

    final job = await release();

    expect(job.state, JobState.failed);
    expect(job.steps.first.message, contains('credentials: apple_id'));
    expect(
      job.steps.first.message,
      contains('Create a new app-specific password at appleid.apple.com'),
    );
    expect(build.runs, isEmpty);
    expect(
      utf8.decode(utf8.encode(job.steps.first.message!)),
      isNot(contains('abcd-efgh')),
    );
  });

  test("a key that cannot see the flavor's app fails preflight", () async {
    await save(CredentialKind.ascKey);
    // The app moves to another team: the key no longer sees it.
    asc.apps.clear();
    clock.advance(const Duration(days: 1));
    await credentials.checkAll();

    final job = await release();

    expect(job.state, JobState.failed);
    expect(
      job.steps.first.message,
      contains('sees no app with the bundle id com.mataa.app'),
    );
    expect(build.runs, isEmpty);
  });

  test('replacing the credential lets the job through again', () async {
    await save(CredentialKind.ascKey);
    asc.failure = const AscAuthException('Provided credentials are not valid.');
    await credentials.checkAll();
    expect((await release()).state, JobState.failed);

    await save(CredentialKind.ascKey);

    expect((await release()).state, JobState.succeeded);
  });
}
