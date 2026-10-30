import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/stores/apple/app_store_profiles.dart';

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
/// - **The dart-define file (ADR 0016):** a secret key is granted when a build
///   step names it in `dartDefineSecret` **and** it is a `dart_defines`
///   credential of the project.
/// - **The Linux iOS signing (ADR 0014):** a secret key is granted when a
///   step names it (`build.ios` in `linuxSigning`) **and** it is an Apple
///   Distribution identity of the project, its certificate, or the App Store
///   profile the engine makes for it and a bundle id of a flavor that uses
///   it (`AppStoreProfiles`).
///
/// Every other secret (the GitHub token, store credentials and the App Store
/// Connect key above all, a key a `command` step names that is none of these)
/// stays on the engine.
///
/// A Mac signs with the identities in its own keychain.
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
        for (final field in const [
          'secretFiles',
          'secretEnvironment',
          'linuxSigning',
        ])
          if (step.input[field] case final Map<dynamic, dynamic> map)
            for (final value in map.values)
              if (value is String) value,
        if (step.input['tokenSecret'] case final String token) token,
        if (step.input['dartDefineSecret'] case final String defines) defines,
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
        ] else if (credential.kind == CredentialKind.shorebird ||
            credential.kind == CredentialKind.dartDefines)
          credential.secretKey
        else if (credential.kind == CredentialKind.appleDistribution) ...[
          credential.secretKey,
          AppleDistributionMaterial.certificateKey(credential.secretKey),
          if (credential.flavor.iosBundleId case final bundleId?)
            AppStoreProfiles.keyFor(credential.secretKey, bundleId),
        ],
    };
    return named.intersection(grantable);
  }
}
