import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';
import '../../helpers/job_harness.dart';
import '../../helpers/workflow_fixtures.dart';

ProjectRecord _on(String id, String host) {
  final project = demoProject(id: id);
  return ProjectRecord(
    id: project.id,
    host: host,
    sourceKey: id,
    fullName: project.fullName,
    remote: 'git@$host:octo/demo.git',
    githubDefaultBranch: project.githubDefaultBranch,
    scan: project.scan,
    findings: project.findings,
    scannedAt: project.scannedAt,
  );
}

CredentialRecord _credential(String name, CredentialStatus status) =>
    CredentialRecord(
      id: 'crd_$name',
      name: name,
      kind: CredentialKind.ascKey,
      secretKey: 'credential.$name',
    ).checked(status: status, at: DateTime.utc(2026, 10, 25));

void main() {
  late BytesSecretStore secrets;
  late FakeCredentialVerifier verifier;
  late InMemoryCredentialRepository credentials;
  late InMemoryProjectRepository projects;
  late FakeProcessRunner runner;
  late EngineDoctor doctor;

  EngineDoctor build({Duration sshTimeout = const Duration(seconds: 20)}) =>
      EngineDoctor(
        local: const ProbeFindings(
          capabilities: {Capability.android, Capability.flutter},
          missing: [
            MissingCapability(
              capability: 'ios-sign',
              reason: 'no Xcode: xcodebuild not found',
              fix: 'install Xcode',
            ),
            MissingCapability(
              capability: 'ios-sign',
              reason: 'not macOS',
              fix: 'use a Mac',
            ),
          ],
        ),
        github: GitHubTokenService(
          secrets: secrets,
          verifier: verifier,
          cli: FakeGitHubCliToken(),
          masker: ReplacingMasker(),
        ),
        credentials: credentials,
        projects: projects,
        runner: runner,
        sshTimeout: sshTimeout,
      );

  setUp(() {
    secrets = BytesSecretStore();
    verifier = FakeCredentialVerifier(CredentialKind.github);
    credentials = InMemoryCredentialRepository();
    projects = InMemoryProjectRepository();
    runner = FakeProcessRunner(
      (call) => const ProcessOutput(
        exitCode: 0,
        stderr: 'authenticated via ssh key.\n',
      ),
    );
    doctor = build();
  });

  Future<Map<String, EngineCheck>> examine() async => {
    for (final check in (await doctor.examine()).checks) check.name: check,
  };

  test(
    'lists the capabilities of its runner, with why one is not there',
    () async {
      final checks = await doctor.examine();

      expect(checks.checks.take(3), [
        const EngineCheck(
          name: 'ios-sign',
          state: CheckState.skipped,
          detail: 'no Xcode: xcodebuild not found; not macOS',
          fix: 'install Xcode; use a Mac',
        ),
        const EngineCheck(name: 'android', state: CheckState.ok),
        const EngineCheck(name: 'flutter', state: CheckState.ok),
      ]);
      expect(checks.healthy, isTrue, reason: 'a runner can take ios-sign');
    },
  );

  test(
    'without a GitHub token or credentials says so, and checks no SSH',
    () async {
      await projects.add(demoProject());

      final checks = await examine();

      expect(checks['secrets']!.state, CheckState.ok);
      expect(
        checks['github'],
        const EngineCheck(
          name: 'github',
          state: CheckState.skipped,
          detail: 'no GitHub token; projects on GitHub need one',
          fix: 'connect GitHub in the settings of the app',
        ),
      );
      expect(checks['credentials']!.detail, 'none yet');
      expect(
        runner.calls,
        isEmpty,
        reason: 'a GitHub project needs no SSH check',
      );
    },
  );

  test(
    'says who the GitHub token belongs to, or why GitHub refused it',
    () async {
      await secrets.write(githubTokenSecretKey, 'ghp_x');
      verifier.answers
        ..add(const VerificationResult.verified(account: 'octo'))
        ..add(const VerificationResult.rejected('Bad.', fix: 'Save another.'))
        ..add(const VerificationResult.rejected('Bad.'))
        ..add(const VerificationResult.unreachable('GitHub is down.'))
        ..add(const VerificationResult.verified());

      expect(
        (await examine())['github'],
        const EngineCheck(
          name: 'github',
          state: CheckState.ok,
          detail: 'as octo',
        ),
      );
      expect(
        (await examine())['github'],
        const EngineCheck(
          name: 'github',
          state: CheckState.missing,
          detail: 'Bad',
          fix: 'Save another',
        ),
      );
      expect((await examine())['github']!.fix, 'save a new GitHub token');
      expect(
        (await examine())['github'],
        const EngineCheck(
          name: 'github',
          state: CheckState.skipped,
          detail: 'GitHub is down',
        ),
      );
      expect(
        (await examine())['github'],
        const EngineCheck(name: 'github', state: CheckState.ok),
      );
    },
  );

  test('finds the secrets locked', () async {
    secrets.failure = const SecretsLockedException('The secrets are locked.');

    final checks = await examine();

    expect(
      checks['secrets'],
      const EngineCheck(
        name: 'secrets',
        state: CheckState.missing,
        detail: 'The secrets are locked.',
        fix: 'unlock the secrets of the engine',
      ),
    );
    expect(checks['github']!.state, CheckState.skipped);
  });

  test('names the credentials refused at their last check', () async {
    await credentials.save(_credential('team', CredentialStatus.verified));

    expect(
      (await examine())['credentials'],
      const EngineCheck(
        name: 'credentials',
        state: CheckState.ok,
        detail: '1 kept, none refused at its last check',
      ),
    );

    await credentials.save(_credential('play', CredentialStatus.rejected));
    expect(
      (await examine())['credentials'],
      const EngineCheck(
        name: 'credentials',
        state: CheckState.missing,
        detail: 'refused at the last check: play',
        fix: 'replace the secret of each, or verify it again',
      ),
    );
  });

  group('SSH to the hosts of projects not on GitHub', () {
    setUp(() async {
      await projects.add(_on('prj_2', 'gitlab.com'));
      await projects.add(_on('prj_3', 'bitbucket.org'));
      await projects.add(_on('prj_4', 'bitbucket.org'));
      await projects.add(_on('prj_5', Project.localHost));
    });

    test('asks each host once, in order, accepting a new host key', () async {
      final checks = await examine();

      expect(
        checks['ssh bitbucket.org'],
        const EngineCheck(
          name: 'ssh bitbucket.org',
          state: CheckState.ok,
          detail: 'authenticated via ssh key.',
        ),
      );
      expect(
        [for (final call in runner.calls) call.arguments.last],
        ['git@bitbucket.org', 'git@gitlab.com'],
      );
      expect(
        runner.calls.first.arguments,
        contains('StrictHostKeyChecking=accept-new'),
      );
    });

    test('says what ssh said when the host refuses the key', () async {
      runner.handler = (call) => const ProcessOutput(
        exitCode: 255,
        stderr: 'git@bitbucket.org: Permission denied (publickey).\n',
      );

      final check = (await examine())['ssh bitbucket.org']!;

      expect(check.state, CheckState.missing);
      expect(check.detail, 'git@bitbucket.org: Permission denied (publickey).');
      expect(
        check.fix,
        contains('deploy key of the repository on bitbucket.org'),
      );
    });

    test('says when ssh says nothing, is missing or does not answer', () async {
      runner.handler = (call) => const ProcessOutput(exitCode: 255);
      expect(
        (await examine())['ssh gitlab.com']!.detail,
        'ssh exited with 255',
      );

      runner.startError = const ProcessStartException('ssh', 'not found');
      expect((await examine())['ssh gitlab.com']!.detail, 'ssh not found');

      runner
        ..startError = null
        ..handler = (call) => Completer<ProcessOutput>().future;
      doctor = build(sshTimeout: const Duration(milliseconds: 1));
      final checks = await examine();
      expect(
        checks['ssh gitlab.com']!.detail,
        'gitlab.com did not answer in time',
      );
    });
  });
}
