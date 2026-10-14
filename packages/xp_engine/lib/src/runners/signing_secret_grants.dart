import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/jobs/job_record.dart';

/// Which secrets a runner may be given for the job it leases (D-09).
///
/// Only signing material, only what the steps of the job name, and only
/// because a credential of the project says it is signing material: a secret
/// key is granted when a step names it in `secretFiles` or
/// `secretEnvironment` **and** it is the keystore of the project or one of
/// the keystore's passwords. Every other secret (the GitHub token, store
/// credentials, a key a `command` step names) stays on the engine.
///
/// The Apple signing identities are in the keychain of the Mac that builds;
/// the engine has no copy to hand out.
class SigningSecretGrants {
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
      for (final step in steps)
        for (final field in const ['secretFiles', 'secretEnvironment'])
          if (step.input[field] case final Map<dynamic, dynamic> map)
            for (final value in map.values)
              if (value is String) value,
    };
    if (named.isEmpty) return const {};
    final signing = <String>{
      for (final credential in await _credentials.list(projectId: projectId))
        if (credential.kind == CredentialKind.keystore) ...[
          credential.secretKey,
          KeystoreMaterial.storePasswordKey(credential.secretKey),
          KeystoreMaterial.keyPasswordKey(credential.secretKey),
        ],
    };
    return named.intersection(signing);
  }
}
