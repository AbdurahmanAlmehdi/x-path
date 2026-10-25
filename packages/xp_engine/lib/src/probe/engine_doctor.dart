import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/git/github_token_service.dart';
import 'package:xp_engine/src/probe/runner_probe.dart';
import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';

/// What the engine finds about the machine it runs on (`GET /doctor`, U5b):
/// the capabilities of its own runner, its secrets, its GitHub token, its
/// credentials, and SSH to the git hosts of projects not on GitHub.
///
/// `xp doctor` prints it, rather than probing in the shell of the CLI,
/// which may be on another machine and has another `PATH` and `JAVA_HOME`
/// than the engine's service. The words follow UX-09: no HTTP path or CLI
/// command.
class EngineDoctor {
  /// Creates the doctor. `local` is the probe the engine ran when it
  /// started.
  const new({
    required this._local,
    required this._github,
    required this._credentials,
    required this._projects,
    required this._runner,
    this.sshTimeout = const Duration(seconds: 20),
  });

  /// How long a host has to answer `ssh -T`.
  final Duration sshTimeout;

  final ProbeFindings _local;
  final GitHubTokenService _github;
  final CredentialRepository _credentials;
  final ProjectRepository _projects;
  final ProcessRunner _runner;

  /// Runs every check.
  Future<DoctorResponse> examine() async {
    final (secrets, github) = await _gitHub();
    return DoctorResponse([
      ..._capabilities(),
      secrets,
      github,
      await _credentialCheck(),
      for (final host in await _otherHosts()) await _ssh(host),
    ]);
  }

  List<EngineCheck> _capabilities() => [
    for (final capability in Capability.values)
      if (_local.capabilities.contains(capability))
        EngineCheck(name: capability.wire, state: CheckState.ok)
      else if (_local.missing.where((m) => m.capability == capability.wire)
          case final missing when missing.isNotEmpty)
        EngineCheck(
          name: capability.wire,
          state: CheckState.missing,
          detail: missing.map((m) => m.reason).join('; '),
          fix: missing.map((m) => m.fix).join('; '),
        ),
  ];

  /// The secrets and the GitHub token: reading the token is what finds the
  /// secrets locked.
  Future<(EngineCheck, EngineCheck)> _gitHub() async {
    final GitHubTokenStatus status;
    try {
      status = await _github.status();
    } on SecretsLockedException catch (error) {
      return (
        EngineCheck(
          name: 'secrets',
          state: CheckState.missing,
          detail: error.message,
          fix: 'unlock the secrets of the engine',
        ),
        const EngineCheck(
          name: 'github',
          state: CheckState.skipped,
          detail: 'the secrets are locked',
        ),
      );
    }
    const secrets = EngineCheck(name: 'secrets', state: CheckState.ok);
    final github = switch (status) {
      GitHubTokenStatus(stored: false) => const EngineCheck(
        name: 'github',
        state: CheckState.skipped,
        detail: 'no GitHub token; projects on GitHub need one',
        fix: 'connect GitHub in the settings of the app',
      ),
      GitHubTokenStatus(status: CredentialStatus.verified, :final login) =>
        EngineCheck(
          name: 'github',
          state: CheckState.ok,
          detail: login == null ? null : 'as $login',
        ),
      GitHubTokenStatus(status: CredentialStatus.rejected) => EngineCheck(
        name: 'github',
        state: CheckState.missing,
        detail: _sentence(status.message),
        fix: _sentence(status.fix) ?? 'save a new GitHub token',
      ),
      _ => EngineCheck(
        name: 'github',
        state: CheckState.skipped,
        detail: _sentence(status.message),
      ),
    };
    return (secrets, github);
  }

  Future<EngineCheck> _credentialCheck() async {
    final credentials = await _credentials.list();
    if (credentials.isEmpty) {
      return const EngineCheck(
        name: 'credentials',
        state: CheckState.skipped,
        detail: 'none yet',
      );
    }
    final refused = [
      for (final credential in credentials)
        if (credential.status == CredentialStatus.rejected) credential.name,
    ];
    if (refused.isEmpty) {
      return EngineCheck(
        name: 'credentials',
        state: CheckState.ok,
        detail: '${credentials.length} kept, none refused at its last check',
      );
    }
    return EngineCheck(
      name: 'credentials',
      state: CheckState.missing,
      detail: 'refused at the last check: ${refused.join(', ')}',
      fix: 'replace the secret of each, or verify it again',
    );
  }

  /// The git hosts of the projects not on GitHub, which the engine reaches
  /// with its own SSH key (ADR 0015), sorted.
  Future<List<String>> _otherHosts() async => {
    for (final project in await _projects.list())
      if (project.host != Project.githubHost &&
          project.host != Project.localHost)
        project.host,
  }.toList()..sort();

  Future<EngineCheck> _ssh(String host) async {
    final name = 'ssh $host';
    final ProcessOutput output;
    try {
      // `-T` asks for no shell. The host answers a known key with a greeting
      // and an exit code of its own (Bitbucket 0, GitHub 1); ssh itself
      // fails with 255.
      output = await _runner.run('ssh', [
        '-T',
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=10',
        '-o',
        'StrictHostKeyChecking=accept-new',
        'git@$host',
      ], timeout: sshTimeout);
    } on ProcessStartException {
      return EngineCheck(
        name: name,
        state: CheckState.missing,
        detail: 'ssh not found',
        fix: 'install the OpenSSH client on the engine machine',
      );
    } on TimeoutException {
      return EngineCheck(
        name: name,
        state: CheckState.missing,
        detail: '$host did not answer in time',
        fix: 'check that the engine machine reaches $host on port 22',
      );
    }
    final said = _firstLine('${output.stderr}\n${output.stdout}');
    if (output.exitCode != 255) {
      return EngineCheck(name: name, state: CheckState.ok, detail: said);
    }
    return EngineCheck(
      name: name,
      state: CheckState.missing,
      detail: said ?? 'ssh exited with 255',
      fix:
          'add the SSH key of the engine machine as a deploy key of the '
          'repository on $host',
    );
  }

  static String? _firstLine(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// [text] without its full stop, as a check's detail and fix are written.
  static String? _sentence(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
