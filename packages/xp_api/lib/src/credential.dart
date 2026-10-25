// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'credential.g.dart';

/// What a credential is for. The wire names are the `kind` of the
/// `credential` table.
@JsonEnum(valueField: 'wire')
enum CredentialKind {
  /// An App Store Connect API key (a `.p8` with its key id and issuer id).
  ascKey('asc_key', 'App Store Connect API key'),

  /// An Apple ID with an app-specific password, for `altool`.
  appleId('apple_id', 'Apple ID'),

  /// An Apple Distribution identity (a private key and its certificate),
  /// with which Linux runners sign iOS builds (ADR 0014).
  appleDistribution('apple_distribution', 'Apple Distribution identity'),

  /// A Google Play service account.
  playSa('play_sa', 'Google Play service account'),

  /// A Firebase (Google Cloud) service account for App Distribution.
  firebaseSa('firebase_sa', 'Firebase service account'),

  /// An Android release keystore with its passwords.
  keystore('keystore', 'Android keystore'),

  /// A Shorebird API key (`sb_api_*`).
  shorebird('shorebird', 'Shorebird API key'),

  /// A GitHub token. The engine has one, shared by every project
  /// (`/github-token`); it is not a named credential.
  github('github', 'GitHub token'),

  /// A Slack incoming webhook.
  slack('slack', 'Slack webhook');

  new(this.wire, this.label);

  /// The name on the wire and in the database.
  final String wire;

  /// What people call it, in generated names and messages.
  final String label;

  /// Whether credentials of this kind are named and assigned to flavors.
  /// Only [github] is not: the engine has one GitHub token.
  bool get isNamed => this != github;

  /// The kind called [wire], or `null`.
  static CredentialKind? fromWire(String wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// What the last check of a credential found.
@JsonEnum(valueField: 'wire')
enum CredentialStatus {
  /// It was never checked.
  unverified('unverified'),

  /// The store or tool accepted it at the last check.
  verified('verified'),

  /// The store or tool refused it at the last check: expired, revoked, a
  /// wrong password. A job that needs it fails preflight.
  rejected('rejected'),

  /// The last check could not reach the store or run the tool, so it says
  /// nothing about the credential.
  unreachable('unreachable');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// The longest name a credential may have.
const maxCredentialNameLength = 80;

/// [name] without the blanks around it, if it can name a credential: not
/// empty, at most [maxCredentialNameLength] characters, no control
/// characters.
///
/// Throws a [FormatException] otherwise. Names are unique regardless of case.
String credentialName(Object? name) {
  if (name is! String || name.trim().isEmpty) {
    throw const FormatException('"name" must be a non-empty string.');
  }
  final trimmed = name.trim();
  if (trimmed.length > maxCredentialNameLength) {
    throw const FormatException(
      '"name" must be at most $maxCredentialNameLength characters.',
    );
  }
  if (trimmed.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw const FormatException('"name" must not contain control characters.');
  }
  return trimmed;
}

/// The kind [json] names. Throws a [FormatException] if it names none.
CredentialKind _kindOf(Object? json) {
  final kind = json is String ? CredentialKind.fromWire(json) : null;
  if (kind == null) {
    throw FormatException(
      '"kind" must be one of '
      '${CredentialKind.values.map((kind) => kind.wire).join(', ')}.',
    );
  }
  return kind;
}

/// The fields of [json] but [known]: the secret fields of a kind.
Map<String, dynamic> _secretFields(
  Map<String, dynamic> json,
  Set<String> known,
) => {
  for (final entry in json.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
};

/// The credential a flavor uses for one kind, as the API shows it: the named
/// credential assigned to the flavor, with what preflight makes of it. It
/// never carries the secret.
///
/// [status], [message] and [fix] combine the two checks: the credential's own
/// ([credentialStatus]: does it authenticate) and the assignment's
/// ([assignmentStatus]: can it reach this flavor's bundle id, package or
/// app). A refusal of either is a refusal.
@JsonSerializable(includeIfNull: false)
class Credential extends Equatable {
  /// Creates a credential.
  const new({
    required this.id,
    required this.projectId,
    required this.app,
    required this.flavor,
    required this.kind,
    required this.status,
    this.name,
    this.account,
    this.verifiedAt,
    this.checkedAt,
    this.message,
    this.fix,
    this.credentialStatus,
    this.assignmentStatus,
  });

  /// Reads a credential from its JSON form.
  factory Credential.fromJson(Map<String, dynamic> json) =>
      _$CredentialFromJson(json);

  /// The engine's id of the named credential, for example
  /// `crd_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The name of the credential, for example "Personal Apple Dev Account".
  final String? name;

  /// The project of the flavor.
  final String projectId;

  /// The path of the app of the flavor; `.` for the root.
  final String app;

  /// The flavor name.
  final String flavor;

  /// What it is for.
  final CredentialKind kind;

  /// What the last checks found, together: what preflight goes by.
  final CredentialStatus status;

  /// Who it belongs to, when that is not secret: the Apple ID, the key id,
  /// the service account email, the keystore alias, the GitHub login.
  final String? account;

  /// When a check last accepted it, in UTC.
  final DateTime? verifiedAt;

  /// When it was last checked, in UTC.
  final DateTime? checkedAt;

  /// What the last check found out, when it did not accept the credential.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// What the last check of the credential itself found: does it
  /// authenticate.
  final CredentialStatus? credentialStatus;

  /// What the last check of the assignment found: can the credential reach
  /// this flavor's bundle id, package or app.
  final CredentialStatus? assignmentStatus;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CredentialToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    projectId,
    app,
    flavor,
    kind,
    status,
    account,
    verifiedAt,
    checkedAt,
    message,
    fix,
    credentialStatus,
    assignmentStatus,
  ];
}

/// The body of `GET /projects/{id}/credentials`: the credential each flavor
/// of the project uses, for each kind it has one of.
@JsonSerializable(explicitToJson: true)
class CredentialsResponse extends Equatable {
  /// Creates the list.
  const new(this.credentials);

  /// Reads the list from its JSON form.
  factory CredentialsResponse.fromJson(Map<String, dynamic> json) =>
      _$CredentialsResponseFromJson(json);

  /// The credentials, by app, flavor and kind.
  final List<Credential> credentials;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CredentialsResponseToJson(this);

  @override
  List<Object?> get props => [credentials];
}

/// A flavor that uses a named credential, with what the check of the
/// assignment found: can the credential reach the flavor's bundle id,
/// package or app.
@JsonSerializable(includeIfNull: false)
class CredentialUsage extends Equatable {
  /// Creates the usage.
  const new({
    required this.projectId,
    required this.app,
    required this.flavor,
    required this.status,
    this.project,
    this.verifiedAt,
    this.checkedAt,
    this.message,
    this.fix,
  });

  /// Reads a usage from its JSON form.
  factory CredentialUsage.fromJson(Map<String, dynamic> json) =>
      _$CredentialUsageFromJson(json);

  /// The project of the flavor.
  final String projectId;

  /// The name of the project (`owner/repository`), when known.
  final String? project;

  /// The path of the app of the flavor; `.` for the root.
  final String app;

  /// The flavor name.
  final String flavor;

  /// What the last check of the assignment found.
  final CredentialStatus status;

  /// When a check of the assignment last accepted it, in UTC.
  final DateTime? verifiedAt;

  /// When the assignment was last checked, in UTC.
  final DateTime? checkedAt;

  /// Why the last check did not accept the assignment.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CredentialUsageToJson(this);

  @override
  List<Object?> get props => [
    projectId,
    project,
    app,
    flavor,
    status,
    verifiedAt,
    checkedAt,
    message,
    fix,
  ];
}

/// A named credential of the engine, as the API shows it: any flavor of any
/// project may use it. It never carries the secret.
@JsonSerializable(includeIfNull: false, explicitToJson: true)
class NamedCredential extends Equatable {
  /// Creates the credential.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.account,
    this.verifiedAt,
    this.checkedAt,
    this.message,
    this.fix,
    this.usedBy = const [],
  });

  /// Reads a credential from its JSON form.
  factory NamedCredential.fromJson(Map<String, dynamic> json) =>
      _$NamedCredentialFromJson(json);

  /// The engine's id, for example `crd_1a2b3c4d5e6f7a8b`. It never changes,
  /// whatever the name or the secret become.
  final String id;

  /// The name, unique regardless of case.
  final String name;

  /// What it is for.
  final CredentialKind kind;

  /// What the last check of the credential found: does it authenticate.
  final CredentialStatus status;

  /// Who it belongs to, when that is not secret: the Apple ID, the key id,
  /// the service account email, the keystore alias.
  final String? account;

  /// When a check last accepted it, in UTC.
  final DateTime? verifiedAt;

  /// When it was last checked, in UTC.
  final DateTime? checkedAt;

  /// Why the last check did not accept it.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// The flavors that use it, by project, app and flavor.
  @JsonKey(defaultValue: <CredentialUsage>[])
  final List<CredentialUsage> usedBy;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$NamedCredentialToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    status,
    account,
    verifiedAt,
    checkedAt,
    message,
    fix,
    usedBy,
  ];
}

/// The body of `GET /credentials`.
@JsonSerializable(explicitToJson: true)
class NamedCredentialsResponse extends Equatable {
  /// Creates the list.
  const new(this.credentials);

  /// Reads the list from its JSON form.
  factory NamedCredentialsResponse.fromJson(Map<String, dynamic> json) =>
      _$NamedCredentialsResponseFromJson(json);

  /// The credentials, by name.
  final List<NamedCredential> credentials;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$NamedCredentialsResponseToJson(this);

  @override
  List<Object?> get props => [credentials];
}

/// The body of `POST /credentials`: the [name], the [kind] and the secret
/// fields of the kind ([material]):
///
/// - `asc_key`: `keyId`, `issuerId`, `privateKey` (the `.p8` text) and
///   `keyKind` (`team` or `individual`, default `team`);
/// - `apple_id`: `appleId` and `password` (an app-specific password);
/// - `apple_distribution`: `privateKey` (PEM) and `certificate` (base64 DER,
///   or PEM);
/// - `play_sa` and `firebase_sa`: `serviceAccount` (the text of the JSON key
///   file);
/// - `keystore`: `keystore` (base64), `storePassword`, `keyAlias` and
///   `keyPassword` (default: the store password);
/// - `shorebird`: `token`;
/// - `slack`: `webhookUrl`.
class CreateCredentialRequest extends Equatable {
  /// Creates a request.
  const new({required this.name, required this.kind, required this.material});

  /// Reads a request from its JSON form.
  ///
  /// Throws a [FormatException] if `name` is not a usable name or `kind` is
  /// not one of [CredentialKind].
  factory CreateCredentialRequest.fromJson(Map<String, dynamic> json) =>
      CreateCredentialRequest(
        name: credentialName(json['name']),
        kind: _kindOf(json['kind']),
        material: _secretFields(json, const {'name', 'kind'}),
      );

  /// The name.
  final String name;

  /// What the credential is for.
  final CredentialKind kind;

  /// The secret fields of [kind]. The engine reads them and never repeats
  /// them.
  final Map<String, dynamic> material;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.wire,
    ...material,
  };

  @override
  List<Object?> get props => [name, kind, material];

  /// Names the request without the secret.
  @override
  String toString() => 'CreateCredentialRequest($name, ${kind.wire})';
}

/// The body of `PUT /credentials/{id}`: a new secret for the credential, the
/// fields of its kind (as in [CreateCredentialRequest]). The name, the id and
/// every assignment stay.
class ReplaceCredentialRequest extends Equatable {
  /// Creates a request.
  const new(this.material);

  /// Reads a request from its JSON form. A `kind` in it is left out; the
  /// credential's kind decides the fields.
  factory ReplaceCredentialRequest.fromJson(Map<String, dynamic> json) =>
      ReplaceCredentialRequest(_secretFields(json, const {'kind'}));

  /// The secret fields. The engine reads them and never repeats them.
  final Map<String, dynamic> material;

  /// The JSON form.
  Map<String, dynamic> toJson() => {...material};

  @override
  List<Object?> get props => [material];

  /// Names the request without the secret.
  @override
  String toString() => 'ReplaceCredentialRequest(${material.keys.join(', ')})';
}

/// The body of `PATCH /credentials/{id}`: a new name.
class RenameCredentialRequest extends Equatable {
  /// Creates a request.
  const new(this.name);

  /// Reads a request from its JSON form.
  ///
  /// Throws a [FormatException] if `name` is not a usable name.
  factory RenameCredentialRequest.fromJson(Map<String, dynamic> json) =>
      RenameCredentialRequest(credentialName(json['name']));

  /// The new name.
  final String name;

  /// The JSON form.
  Map<String, dynamic> toJson() => {'name': name};

  @override
  List<Object?> get props => [name];
}

/// The body of `PUT /projects/{id}/flavors/{flavor}/credentials/{kind}`:
/// which credential the flavor uses for the kind.
///
/// With [allFlavors] every flavor of the app gets it too; a flavor that has
/// another credential of the kind keeps it unless [replace].
@JsonSerializable(checked: true)
class AssignCredentialRequest extends Equatable {
  /// Creates a request.
  const new({
    required this.credentialId,
    this.allFlavors = false,
    this.replace = false,
  });

  /// Reads a request from its JSON form.
  factory AssignCredentialRequest.fromJson(Map<String, dynamic> json) =>
      _$AssignCredentialRequestFromJson(json);

  /// The named credential, by id.
  final String credentialId;

  /// Whether every flavor of the app uses it, not only this one.
  @JsonKey(defaultValue: false)
  final bool allFlavors;

  /// Whether the other flavors of the app give up the credential of the kind
  /// they have. Only with [allFlavors].
  @JsonKey(defaultValue: false)
  final bool replace;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$AssignCredentialRequestToJson(this);

  @override
  List<Object?> get props => [credentialId, allFlavors, replace];
}

/// The answer of an assignment: the flavors that use the credential now, and
/// those that kept another credential of the kind (no `replace`).
@JsonSerializable(explicitToJson: true)
class AssignCredentialResponse extends Equatable {
  /// Creates the answer.
  const new({required this.assigned, this.kept = const []});

  /// Reads the answer from its JSON form.
  factory AssignCredentialResponse.fromJson(Map<String, dynamic> json) =>
      _$AssignCredentialResponseFromJson(json);

  /// The flavors that use the credential now, with their checks.
  final List<Credential> assigned;

  /// The flavors that kept the credential they had.
  @JsonKey(defaultValue: <Credential>[])
  final List<Credential> kept;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$AssignCredentialResponseToJson(this);

  @override
  List<Object?> get props => [assigned, kept];
}

/// The body of `PUT /projects/{id}/credentials` (deprecated: use
/// `POST /credentials` and an assignment): which flavor and kind, the secret
/// material, whose fields depend on the kind (as in
/// [CreateCredentialRequest]; a `github` token is the engine's), and
/// optionally the [name] of the credential it creates.
class SaveCredentialRequest extends Equatable {
  /// Creates a request.
  const new({
    required this.flavor,
    required this.kind,
    required this.material,
    this.app = '.',
    this.name,
  });

  /// Reads a request from its JSON form.
  ///
  /// Throws a [FormatException] if `flavor` or `kind` is missing, not a
  /// string, `kind` is not one of [CredentialKind] or `name` is given and
  /// is not a usable name.
  factory SaveCredentialRequest.fromJson(Map<String, dynamic> json) {
    final app = json['app'];
    final flavor = json['flavor'];
    final name = json['name'];
    if (app != null && (app is! String || app.isEmpty)) {
      throw const FormatException('"app" must be a non-empty string.');
    }
    if (flavor is! String || flavor.isEmpty) {
      throw const FormatException('"flavor" must be a non-empty string.');
    }
    return SaveCredentialRequest(
      app: app as String? ?? '.',
      flavor: flavor,
      kind: _kindOf(json['kind']),
      name: name == null ? null : credentialName(name),
      material: _secretFields(json, const {'app', 'flavor', 'kind', 'name'}),
    );
  }

  /// The path of the app; `.` for the app at the root.
  final String app;

  /// The flavor name; `default` for an app without flavors.
  final String flavor;

  /// What the credential is for.
  final CredentialKind kind;

  /// The name of the credential it creates; the engine makes one up when
  /// absent.
  final String? name;

  /// The secret fields of [kind]. The engine reads them and never repeats
  /// them.
  final Map<String, dynamic> material;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'app': app,
    'flavor': flavor,
    'kind': kind.wire,
    'name': ?name,
    ...material,
  };

  @override
  List<Object?> get props => [app, flavor, kind, name, material];

  /// Names the request without the secret.
  @override
  String toString() => 'SaveCredentialRequest($app, $flavor, ${kind.wire})';
}
