import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// A flavor that may use credentials, with the identifiers a check of an
/// assignment may need.
class CredentialFlavor extends Equatable {
  /// Creates a flavor.
  const new({
    required this.id,
    required this.projectId,
    required this.appPath,
    required this.name,
    this.projectName,
    this.iosBundleId,
    this.androidAppId,
  });

  /// The engine's id of the flavor, for example `flv_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project.
  final String projectId;

  /// The name of the project (`owner/repository`), when known.
  final String? projectName;

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
    projectName,
    appPath,
    name,
    iosBundleId,
    androidAppId,
  ];
}

/// What a check found, as it is kept: of a credential, or of its assignment
/// to a flavor.
class CredentialCheck extends Equatable {
  /// Creates the outcome.
  const new({
    this.status = CredentialStatus.unverified,
    this.verifiedAt,
    this.checkedAt,
    this.message,
    this.fix,
  });

  /// What the last check found.
  final CredentialStatus status;

  /// When a check last accepted it.
  final DateTime? verifiedAt;

  /// When it was last checked.
  final DateTime? checkedAt;

  /// What the last check said, if it did not accept it.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// The outcome of a check made [at]. [message] and [fix] are replaced (a
  /// check that accepts clears them).
  CredentialCheck after({
    required CredentialStatus status,
    required DateTime at,
    String? message,
    String? fix,
  }) => CredentialCheck(
    status: status,
    verifiedAt: status == CredentialStatus.verified ? at : verifiedAt,
    checkedAt: at,
    message: message,
    fix: fix,
  );

  @override
  List<Object?> get props => [status, verifiedAt, checkedAt, message, fix];
}

/// A named credential (a `credential` row): its name, where its secret is
/// kept and what the last check of it found. It holds no secret.
class CredentialRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.secretKey,
    this.account,
    this.check = const CredentialCheck(),
  });

  /// The engine's id, for example `crd_1a2b3c4d5e6f7a8b`. It never changes.
  final String id;

  /// The name, unique regardless of case.
  final String name;

  /// What it is for.
  final CredentialKind kind;

  /// The key in the secret store of the secret (the base of the keys for a
  /// keystore).
  final String secretKey;

  /// Who it belongs to, when that is not secret.
  final String? account;

  /// What the last check of the credential found: does it authenticate.
  final CredentialCheck check;

  /// What the last check found.
  CredentialStatus get status => check.status;

  /// A copy with the outcome of a check made [at].
  CredentialRecord checked({
    required CredentialStatus status,
    required DateTime at,
    String? account,
    String? message,
    String? fix,
  }) => CredentialRecord(
    id: id,
    name: name,
    kind: kind,
    secretKey: secretKey,
    account: account ?? this.account,
    check: check.after(status: status, at: at, message: message, fix: fix),
  );

  /// A copy called [name].
  CredentialRecord renamed(String name) => CredentialRecord(
    id: id,
    name: name,
    kind: kind,
    secretKey: secretKey,
    account: account,
    check: check,
  );

  /// The API form, used by the flavors of [usages].
  NamedCredential toApi([Iterable<AssignedCredential> usages = const []]) =>
      NamedCredential(
        id: id,
        name: name,
        kind: kind,
        status: check.status,
        account: account,
        verifiedAt: check.verifiedAt,
        checkedAt: check.checkedAt,
        message: check.message,
        fix: check.fix,
        usedBy: [for (final usage in usages) usage.toUsage()],
      );

  @override
  List<Object?> get props => [id, name, kind, secretKey, account, check];
}

/// A credential assigned to a flavor (a `credential_assignment` row with its
/// `credential`): the one the flavor uses for the credential's kind, and what
/// the last check of the assignment found (can the credential reach the
/// flavor's bundle id, package or app).
class AssignedCredential extends Equatable {
  /// Creates the assignment.
  const new({
    required this.flavor,
    required this.credential,
    this.check = const CredentialCheck(),
  });

  /// The flavor.
  final CredentialFlavor flavor;

  /// The credential it uses.
  final CredentialRecord credential;

  /// What the last check of the assignment found.
  final CredentialCheck check;

  /// The id of the credential.
  String get id => credential.id;

  /// The kind.
  CredentialKind get kind => credential.kind;

  /// Where the credential's secret is kept.
  String get secretKey => credential.secretKey;

  /// Who the credential belongs to, when that is not secret.
  String? get account => credential.account;

  /// What preflight makes of the two checks: a refusal of either is a
  /// refusal, both must accept for an acceptance, and otherwise the
  /// credential is not confirmed (a check that could not be made comes
  /// before one never made).
  CredentialStatus get status {
    final both = [credential.status, check.status];
    if (both.contains(CredentialStatus.rejected)) {
      return CredentialStatus.rejected;
    }
    if (both.every((status) => status == CredentialStatus.verified)) {
      return CredentialStatus.verified;
    }
    if (both.contains(CredentialStatus.unreachable)) {
      return CredentialStatus.unreachable;
    }
    return CredentialStatus.unverified;
  }

  /// What the check that did not accept says: the credential's first.
  String? get message => credential.check.message ?? check.message;

  /// What to do about [message].
  String? get fix =>
      credential.check.message != null ? credential.check.fix : check.fix;

  /// A copy with the outcome of a check of the assignment made [at].
  AssignedCredential checked({
    required CredentialStatus status,
    required DateTime at,
    String? message,
    String? fix,
  }) => AssignedCredential(
    flavor: flavor,
    credential: credential,
    check: check.after(status: status, at: at, message: message, fix: fix),
  );

  /// The same assignment of [credential] (with its latest state).
  AssignedCredential withCredential(CredentialRecord credential) =>
      AssignedCredential(flavor: flavor, credential: credential, check: check);

  /// The API form, as the flavor sees it.
  Credential toApi() {
    final times = [?credential.check.checkedAt, ?check.checkedAt]..sort();
    final verified = [?credential.check.verifiedAt, ?check.verifiedAt]..sort();
    return Credential(
      id: credential.id,
      name: credential.name,
      projectId: flavor.projectId,
      app: flavor.appPath,
      flavor: flavor.name,
      kind: kind,
      status: status,
      account: account,
      verifiedAt: status == CredentialStatus.verified ? verified.first : null,
      checkedAt: times.firstOrNull,
      message: message,
      fix: fix,
      credentialStatus: credential.status,
      assignmentStatus: check.status,
    );
  }

  /// The API form, as the credential's list of usages shows it.
  CredentialUsage toUsage() => CredentialUsage(
    projectId: flavor.projectId,
    project: flavor.projectName,
    app: flavor.appPath,
    flavor: flavor.name,
    status: check.status,
    verifiedAt: check.verifiedAt,
    checkedAt: check.checkedAt,
    message: check.message,
    fix: check.fix,
  );

  @override
  List<Object?> get props => [flavor, credential, check];
}
