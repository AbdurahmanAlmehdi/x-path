import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The token endpoint Google's service account files name.
const googleTokenUri = 'https://oauth2.googleapis.com/token';

/// A Google service account key: what XPath signs its OAuth2 assertions with
/// to talk to the Google Play Developer API (D-15).
///
/// The secret store keeps the JSON file Google Cloud gives out, as it is (the
/// naming convention for the `secret_key` of a `play_sa` credential
/// reference):
///
/// ```json
/// {"type": "service_account",
///  "client_email": "xpath@project.iam.gserviceaccount.com",
///  "private_key_id": "...", "private_key": "-----BEGIN PRIVATE KEY-----\n...",
///  "token_uri": "https://oauth2.googleapis.com/token"}
/// ```
///
/// Other fields of the file (`project_id`, `client_id`, ...) are ignored.
class PlayServiceAccount extends Equatable {
  /// Creates a service account.
  const new({
    required this.clientEmail,
    required this.privateKey,
    this.privateKeyId,
    this.tokenUri = googleTokenUri,
  });

  /// Reads the JSON of a service account key file.
  ///
  /// Throws a [FormatException] if [json] is not that object. The message
  /// never contains the private key.
  factory fromSecret(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('The service account key is not JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'The service account key must be a JSON object.',
      );
    }
    final fields = decoded;
    String? text(String name) {
      final value = fields[name];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    String required(String name) =>
        text(name) ??
        (throw FormatException('The service account key needs "$name".'));

    final type = fields['type'];
    if (type != null && type != 'service_account') {
      throw const FormatException(
        'The key is not a service account key ("type" must be '
        '"service_account").',
      );
    }
    final tokenUri = text('token_uri') ?? googleTokenUri;
    final uri = Uri.tryParse(tokenUri);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('"token_uri" must be an absolute URL.');
    }
    return PlayServiceAccount(
      clientEmail: required('client_email'),
      privateKey: required('private_key'),
      privateKeyId: text('private_key_id'),
      tokenUri: tokenUri,
    );
  }

  /// The email of the service account, the `iss` of its assertions. Invite it
  /// in the Play Console (Users and permissions).
  final String clientEmail;

  /// The private key, a PKCS#8 `-----BEGIN PRIVATE KEY-----` block.
  final String privateKey;

  /// The id of the key (`kid`), if the file has one.
  final String? privateKeyId;

  /// Where the signed assertion is exchanged for an access token. It is also
  /// the `aud` of the assertion.
  final String tokenUri;

  /// The JSON to keep in the secret store.
  String toSecret() => jsonEncode({
    'type': 'service_account',
    'client_email': clientEmail,
    'private_key': privateKey,
    'private_key_id': ?privateKeyId,
    'token_uri': tokenUri,
  });

  @override
  List<Object?> get props => [clientEmail, privateKey, privateKeyId, tokenUri];

  /// Names the account without its private part.
  @override
  String toString() => 'PlayServiceAccount($clientEmail)';
}
