import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_record.dart';

/// What a check of a credential found.
class VerificationResult extends Equatable {
  /// The store or tool accepted the credential. [account] is who it belongs
  /// to, when the check learned that (a GitHub login).
  const new verified({this.account})
    : status = CredentialStatus.verified,
      message = null,
      fix = null;

  /// The store or tool refused the credential: it expired, was revoked, or
  /// is wrong. A job that needs it must not start.
  const new rejected(String this.message, {this.fix})
    : status = CredentialStatus.rejected,
      account = null;

  /// The check could not tell: the store was not reachable or the tool is
  /// missing. It says nothing about the credential.
  const new unreachable(String this.message, {this.fix})
    : status = CredentialStatus.unreachable,
      account = null;

  /// [CredentialStatus.verified], [CredentialStatus.rejected] or
  /// [CredentialStatus.unreachable].
  final CredentialStatus status;

  /// Why the credential was not accepted. Never contains a secret.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// Who the credential belongs to, if the check found out.
  final String? account;

  @override
  List<Object?> get props => [status, message, fix, account];
}

/// The flavor a credential is checked for: a check may use its identifiers.
class CredentialTarget extends Equatable {
  /// Creates a target.
  const new({this.iosBundleId, this.androidAppId});

  /// The target of the flavor [flavor].
  new of(CredentialFlavor flavor)
    : iosBundleId = flavor.iosBundleId,
      androidAppId = flavor.androidAppId;

  /// The iOS bundle id of the flavor.
  final String? iosBundleId;

  /// The Android application id of the flavor.
  final String? androidAppId;

  @override
  List<Object?> get props => [iosBundleId, androidAppId];
}

/// Checks the credentials of one kind with the store or tool they are for,
/// with a cheap read that changes nothing.
///
/// A verifier turns the failures it expects into a [VerificationResult]; it
/// does not throw them. `xp_engine` has the verifiers that need nothing but
/// its own ports, `xp_adapters` the ones that need a CLI or HTTP of their own.
abstract interface class CredentialVerifier {
  /// The kind it checks.
  CredentialKind get kind;

  /// Checks [material], which is of [kind].
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  );
}

/// A [CredentialVerifier] that answers what the test says.
class FakeCredentialVerifier implements CredentialVerifier {
  /// Creates a verifier of [kind] that accepts everything.
  new(this.kind);

  @override
  final CredentialKind kind;

  /// What the next calls answer, in order; when empty the verifier accepts.
  final answers = <VerificationResult>[];

  /// The material of every call, oldest first.
  final checked = <CredentialMaterial>[];

  /// The target of every call, oldest first.
  final targets = <CredentialTarget>[];

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    checked.add(material);
    targets.add(target);
    return answers.isEmpty
        ? const VerificationResult.verified()
        : answers.removeAt(0);
  }
}
