import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Which kind of App Store Connect API key it is.
///
/// Apple signs the two kinds of token differently (ES256 for both, but a team
/// key names its issuer and an individual key says `sub: user`), and altool
/// tells them apart by the file name of the `.p8`.
enum AscKeyKind {
  /// A team key (App Store Connect, Users and Access, Integrations). The
  /// token names the issuer.
  team('team', 'AuthKey_'),

  /// An individual key (a user's own API access). The token has `sub: user`
  /// and no issuer.
  individual('individual', 'ApiKey_');

  new(this.wire, this._filePrefix);

  /// The name in the stored form of a key.
  final String wire;

  final String _filePrefix;

  /// The name altool expects for the `.p8` of the key [keyId]:
  /// `AuthKey_<id>.p8` for a team key, `ApiKey_<id>.p8` for an individual one.
  String keyFileName(String keyId) => '$_filePrefix$keyId.p8';

  /// The kind called [wire], or `null`.
  static AscKeyKind? fromWire(String wire) =>
      values.where((kind) => kind.wire == wire).firstOrNull;
}

/// An App Store Connect API key: what the REST client signs its tokens with,
/// and what altool uploads with.
///
/// The secret store keeps one value per key, a JSON object (the naming
/// convention for the `secret_key` of an `asc_key` credential reference):
///
/// ```json
/// {"keyId": "ABC123DEF4", "issuerId": "57246542-96fe-1a63-e053-0824d011072a",
///  "keyKind": "team", "privateKey": "-----BEGIN PRIVATE KEY-----\n..."}
/// ```
///
/// `keyKind` is `team` or `individual` and defaults to `team`. `privateKey`
/// is the content of the `.p8` file.
class AscKey extends Equatable {
  /// Creates a key.
  const new({
    required this.keyId,
    required this.issuerId,
    required this.privateKey,
    this.kind = AscKeyKind.team,
  });

  /// Reads the JSON a key is stored as.
  ///
  /// Throws a [FormatException] if [json] is not that object. The message
  /// never contains the private key.
  factory fromSecret(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('The ASC key is not JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The ASC key must be a JSON object.');
    }
    final fields = decoded;
    String field(String name) {
      final value = fields[name];
      if (value is String && value.trim().isNotEmpty) return value;
      throw FormatException('The ASC key needs "$name".');
    }

    final wire = fields['keyKind'] ?? AscKeyKind.team.wire;
    final kind = wire is String ? AscKeyKind.fromWire(wire) : null;
    if (kind == null) {
      throw const FormatException('"keyKind" must be "team" or "individual".');
    }
    return AscKey(
      keyId: field('keyId'),
      issuerId: field('issuerId'),
      privateKey: field('privateKey'),
      kind: kind,
    );
  }

  /// The key id (`kid`), ten characters.
  final String keyId;

  /// The issuer id, the UUID above the key list in App Store Connect.
  final String issuerId;

  /// The content of the `.p8` file.
  final String privateKey;

  /// Team or individual.
  final AscKeyKind kind;

  /// The name altool looks for the `.p8` under.
  String get fileName => kind.keyFileName(keyId);

  /// The JSON to keep in the secret store.
  String toSecret() => jsonEncode({
    'keyId': keyId,
    'issuerId': issuerId,
    'keyKind': kind.wire,
    'privateKey': privateKey,
  });

  @override
  List<Object?> get props => [keyId, issuerId, privateKey, kind];

  /// Names the key without its private part.
  @override
  String toString() => 'AscKey($keyId, ${kind.wire})';
}
