import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/process/process_runner.dart';

/// The variable that carries the keystore password to `keytool`
/// (`-storepass:env`), so that it is never in `ps`.
const keystorePasswordVariable = 'XPATH_KEYSTORE_STOREPASS';

/// A file that holds a secret for a moment and is deleted afterwards.
abstract interface class TemporaryFile {
  /// Where the file is.
  String get path;

  /// Deletes the file. Does nothing if it is gone.
  Future<void> delete();
}

/// Makes short-lived files for secrets, readable by the engine's user only
/// (mode 0600). `xp_adapters` has the `dart:io` implementation.
abstract interface class TemporaryFileStore {
  /// Writes [bytes] to a new file.
  Future<TemporaryFile> create(List<int> bytes);
}

/// Checks an Android keystore by listing the alias with `keytool -list`:
/// the store password must open it and the alias must exist. `keytool` has no
/// check for the key password, so Gradle finds a wrong one at the first
/// build.
///
/// The keystore is written to a private temporary file for the call, and the
/// password reaches `keytool` through the environment, never the arguments.
class KeystoreVerifier implements CredentialVerifier {
  /// Creates the verifier.
  const new({
    required this._runner,
    required this._files,
    this.executable = 'keytool',
    this.timeout = const Duration(seconds: 60),
  });

  /// The program that lists keystores (`keytool` of a JDK).
  final String executable;

  /// How long `keytool` has to answer.
  final Duration timeout;

  final ProcessRunner _runner;
  final TemporaryFileStore _files;

  @override
  CredentialKind get kind => CredentialKind.keystore;

  @override
  bool get checksTarget => false;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final keystore = material as KeystoreMaterial;
    final file = await _files.create(keystore.bytes);
    try {
      final ProcessOutput output;
      try {
        output = await _runner.run(
          executable,
          [
            '-list',
            '-keystore',
            file.path,
            '-storepass:env',
            keystorePasswordVariable,
            '-alias',
            keystore.alias,
          ],
          environment: {keystorePasswordVariable: keystore.storePassword},
          timeout: timeout,
        );
      } on ProcessStartException {
        return const VerificationResult.unreachable(
          'keytool could not be started.',
          fix: 'Install a JDK (keytool is part of it) and put it on the PATH.',
        );
      } on TimeoutException {
        return const VerificationResult.unreachable(
          'keytool did not answer in time.',
          fix: 'Try again.',
        );
      }
      if (output.exitCode == 0) {
        return VerificationResult.verified(account: keystore.alias);
      }
      return _refusal(output, keystore);
    } finally {
      await file.delete();
    }
  }

  VerificationResult _refusal(ProcessOutput output, KeystoreMaterial keystore) {
    final text = '${output.stderr}\n${output.stdout}'.toLowerCase();
    if (text.contains('password was incorrect')) {
      return const VerificationResult.rejected(
        'keytool could not open the keystore: the store password is wrong, '
        'or the file is damaged.',
        fix: 'Save the keystore again with the right store password.',
      );
    }
    if (text.contains('does not exist')) {
      return VerificationResult.rejected(
        'The keystore has no key with the alias "${keystore.alias}".',
        fix:
            'Use the alias of the signing key (keytool -list shows the '
            'aliases) and save the keystore again.',
      );
    }
    return const VerificationResult.rejected(
      'keytool could not read the keystore.',
      fix:
          'Send the keystore file itself (.jks or .keystore, as base64) and '
          'save it again.',
    );
  }
}
