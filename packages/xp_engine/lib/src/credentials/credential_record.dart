import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// The flavor a credential belongs to, with the identifiers a check may need.
class CredentialFlavor extends Equatable {
  /// Creates a flavor.
  const new({
    required this.id,
    required this.projectId,
    required this.appPath,
    required this.name,
    this.iosBundleId,
    this.androidAppId,
  });

  /// The engine's id of the flavor, for example `flv_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project.
  final String projectId;

  /// The path of the app; `.` for the root.
  final String appPath;

  /// The flavor name.
  final String name;

  /// The iOS bundle id.
  final String? iosBundleId;

  /// The Android application id.
  final String? androidAppId;

  @override
  List<Object?> get props => [
    id,
    projectId,
    appPath,
    name,
    iosBundleId,
    androidAppId,
  ];
}

/// A `credential_ref` row: where a credential's secret is kept and what the
/// last check found. It holds no secret.
class CredentialRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.flavor,
    required this.kind,
    required this.secretKey,
    this.account,
    this.status = CredentialStatus.unverified,
    this.verifiedAt,
    this.checkedAt,
    this.message,
    this.fix,
  });

  /// The engine's id, for example `crd_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The flavor it belongs to.
  final CredentialFlavor flavor;

  /// What it is for.
  final CredentialKind kind;

  /// The key in the secret store of the secret (the base of the keys for a
  /// keystore).
  final String secretKey;

  /// Who it belongs to, when that is not secret.
  final String? account;

  /// What the last check found.
  final CredentialStatus status;

  /// When a check last accepted it.
  final DateTime? verifiedAt;

  /// When it was last checked.
  final DateTime? checkedAt;

  /// What the last check said, if it did not accept the credential.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// A copy with the outcome of a check. [message] and [fix] are replaced
  /// (a check that accepts clears them).
  CredentialRecord checked({
    required CredentialStatus status,
    required DateTime at,
    String? account,
    String? message,
    String? fix,
  }) => CredentialRecord(
    id: id,
    flavor: flavor,
    kind: kind,
    secretKey: secretKey,
    account: account ?? this.account,
    status: status,
    verifiedAt: status == CredentialStatus.verified ? at : verifiedAt,
    checkedAt: at,
    message: message,
    fix: fix,
  );

  /// The API form.
  Credential toApi() => Credential(
    id: id,
    projectId: flavor.projectId,
    app: flavor.appPath,
    flavor: flavor.name,
    kind: kind,
    status: status,
    account: account,
    verifiedAt: verifiedAt,
    checkedAt: checkedAt,
    message: message,
    fix: fix,
  );

  @override
  List<Object?> get props => [
    id,
    flavor,
    kind,
    secretKey,
    account,
    status,
    verifiedAt,
    checkedAt,
    message,
    fix,
  ];
}
