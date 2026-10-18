import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/jobs/job_record.dart';

/// Which secrets a runner may be given for the job it leases (D-09, ADR 0012).
///
/// Only what the steps of the job name, and only because a credential of the
/// project says it may travel to a runner:
///
/// - **Signing material (D-09):** a secret key is granted when a step names
///   it in `secretFiles` or `secretEnvironment` **and** it is the keystore of
///   the project or one of the keystore's passwords.
/// - **The Shorebird key (ADR 0012):** a secret key is granted when a step
///   names it in `secretFiles`, `secretEnvironment` or `tokenSecret` (the
///   `shorebird.release` and `shorebird.patch` steps) **and** it is the
///   `sb_api_*` key of a Shorebird credential of the project.
///
/// Every other secret (the GitHub token, store credentials, a key a
/// `command` step names that is none of these) stays on the engine.
///
/// The Apple signing identities are in the keychain of the Mac that builds;
/// the engine has no copy to hand out.
class RunnerSecretGrants {
  /// Creates the grants over the credentials of the projects.
  const new(this._credentials);

  final CredentialRepository _credentials;

  /// The keys the runner of a job of [projectId] may ask for, given the
  /// [steps] of the job.
  Future<Set<String>> forSteps(
    String projectId,
    Iterable<StepRecord> steps,
  ) async {
    final named = <String>{
      for (final step in steps) ...[
        for (final field in const ['secretFiles', 'secretEnvironment'])
          if (step.input[field] case final Map<dynamic, dynamic> map)
            for (final value in map.values)
              if (value is String) value,
        if (step.input['tokenSecret'] case final String token) token,
      ],
    };
    if (named.isEmpty) return const {};
    final grantable = <String>{
      for (final credential in await _credentials.assignments(
        projectId: projectId,
      ))
        if (credential.kind == CredentialKind.keystore) ...[
          credential.secretKey,
          KeystoreMaterial.storePasswordKey(credential.secretKey),
          KeystoreMaterial.keyPasswordKey(credential.secretKey),
        ] else if (credential.kind == CredentialKind.shorebird)
          credential.secretKey,
    };
    return named.intersection(grantable);
  }
}
