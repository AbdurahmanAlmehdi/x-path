// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'credential.g.dart';

/// What a credential is for. The wire names are the `kind` of the
/// `credential_ref` table.
@JsonEnum(valueField: 'wire')
enum CredentialKind {
  /// An App Store Connect API key (a `.p8` with its key id and issuer id).
  ascKey('asc_key'),

  /// An Apple ID with an app-specific password, for `altool`.
  appleId('apple_id'),

  /// A Google Play service account.
  playSa('play_sa'),

  /// A Firebase (Google Cloud) service account for App Distribution.
  firebaseSa('firebase_sa'),

  /// An Android release keystore with its passwords.
  keystore('keystore'),

  /// A Shorebird API key (`sb_api_*`).
  shorebird('shorebird'),

  /// A GitHub token. The engine has one, shared by every project.
  github('github'),

  /// A Slack incoming webhook.
  slack('slack');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;

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

/// A credential of a flavor, as the API shows it. It never carries the
/// secret.
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
    this.account,
    this.verifiedAt,
    this.checkedAt,
    this.message,
    this.fix,
  });

  /// Reads a credential from its JSON form.
  factory Credential.fromJson(Map<String, dynamic> json) =>
      _$CredentialFromJson(json);

  /// The engine's id, for example `crd_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project of the flavor.
  final String projectId;

  /// The path of the app of the flavor; `.` for the root.
  final String app;

  /// The flavor name.
  final String flavor;

  /// What it is for.
  final CredentialKind kind;

  /// What the last check found.
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

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CredentialToJson(this);

  @override
  List<Object?> get props => [
    id,
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
  ];
}

/// The body of `GET /projects/{id}/credentials`.
@JsonSerializable(explicitToJson: true)
class CredentialsResponse extends Equatable {
  /// Creates the list.
  const new(this.credentials);

  /// Reads the list from its JSON form.
  factory CredentialsResponse.fromJson(Map<String, dynamic> json) =>
      _$CredentialsResponseFromJson(json);

  /// The credentials, oldest first.
  final List<Credential> credentials;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CredentialsResponseToJson(this);

  @override
  List<Object?> get props => [credentials];
}

/// The body of `PUT /projects/{id}/credentials`: which flavor and kind, and
/// the secret material, whose fields depend on the kind.
///
/// - `asc_key`: `keyId`, `issuerId`, `privateKey` (the `.p8` text) and
///   `keyKind` (`team` or `individual`, default `team`);
/// - `apple_id`: `appleId` and `password` (an app-specific password);
/// - `play_sa` and `firebase_sa`: `serviceAccount` (the text of the JSON key
///   file);
/// - `keystore`: `keystore` (base64), `storePassword`, `keyAlias` and
///   `keyPassword` (default: the store password);
/// - `shorebird` and `github`: `token`;
/// - `slack`: `webhookUrl`.
class SaveCredentialRequest extends Equatable {
  /// Creates a request.
  const new({
    required this.flavor,
    required this.kind,
    required this.material,
    this.app = '.',
  });

  /// Reads a request from its JSON form.
  ///
  /// Throws a [FormatException] if `flavor` or `kind` is missing, not a
  /// string, or `kind` is not one of [CredentialKind].
  factory SaveCredentialRequest.fromJson(Map<String, dynamic> json) {
    final app = json['app'];
    final flavor = json['flavor'];
    final kind = json['kind'];
    if (app != null && (app is! String || app.isEmpty)) {
      throw const FormatException('"app" must be a non-empty string.');
    }
    if (flavor is! String || flavor.isEmpty) {
      throw const FormatException('"flavor" must be a non-empty string.');
    }
    final parsed = kind is String ? CredentialKind.fromWire(kind) : null;
    if (parsed == null) {
      throw FormatException(
        '"kind" must be one of '
        '${CredentialKind.values.map((kind) => kind.wire).join(', ')}.',
      );
    }
    return SaveCredentialRequest(
      app: app as String? ?? '.',
      flavor: flavor,
      kind: parsed,
      material: {
        for (final entry in json.entries)
          if (entry.key != 'app' &&
              entry.key != 'flavor' &&
              entry.key != 'kind')
            entry.key: entry.value,
      },
    );
  }

  /// The path of the app; `.` for the app at the root.
  final String app;

  /// The flavor name; `default` for an app without flavors.
  final String flavor;

  /// What the credential is for.
  final CredentialKind kind;

  /// The secret fields of [kind]. The engine reads them and never repeats
  /// them.
  final Map<String, dynamic> material;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'app': app,
    'flavor': flavor,
    'kind': kind.wire,
    ...material,
  };

  @override
  List<Object?> get props => [app, flavor, kind, material];

  /// Names the request without the secret.
  @override
  String toString() => 'SaveCredentialRequest($app, $flavor, ${kind.wire})';
}
