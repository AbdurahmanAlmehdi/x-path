import 'dart:convert';
import 'dart:typed_data';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_exceptions.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/stores/apple/asc_key.dart';
import 'package:xp_engine/src/stores/play/play_service_account.dart';

/// The secret part of a credential, as the owner hands it over and as the
/// secret store keeps it.
///
/// How each kind is stored, under the `secret_key` of its reference (the
/// conventions of the store adapters of Phases 10a and 10b, and of the steps
/// that read the secrets):
///
/// | kind | secret store |
/// |---|---|
/// | `asc_key` | `<key>`: JSON `{keyId, issuerId, keyKind, privateKey}` |
/// | `apple_id` | `<key>`: the password; the Apple ID is the `account` |
/// | `play_sa`, `firebase_sa` | `<key>`: the JSON key file, as it is |
/// | `keystore` | `<key>`: bytes; `<key>.storePassword`, `<key>.keyPassword` |
/// | `shorebird`, `github` | `<key>`: the token |
/// | `slack` | `<key>`: the webhook URL |
sealed class CredentialMaterial {
  const new();

  /// Reads the material of a request.
  ///
  /// Throws a [CredentialRequestException] if a field is missing or of the
  /// wrong type, and a [CredentialRejectedException] if the fields cannot be
  /// a credential of [kind] (a service account file that is not one, a
  /// keystore that is not base64). Neither message contains a secret.
  factory fromFields(CredentialKind kind, Map<String, dynamic> fields) {
    String text(String name) {
      final value = fields[name];
      if (value is String && value.trim().isNotEmpty) return value;
      throw CredentialRequestException(
        '"$name" must be a non-empty string for a ${kind.wire} credential.',
      );
    }

    String? optional(String name) {
      final value = fields[name];
      if (value == null) return null;
      if (value is String && value.trim().isNotEmpty) return value;
      throw CredentialRequestException('"$name" must be a non-empty string.');
    }

    switch (kind) {
      case CredentialKind.ascKey:
        final keyKind = optional('keyKind') ?? AscKeyKind.team.wire;
        final parsedKind = AscKeyKind.fromWire(keyKind);
        if (parsedKind == null) {
          throw const CredentialRequestException(
            '"keyKind" must be "team" or "individual".',
          );
        }
        return AscKeyMaterial(
          AscKey(
            keyId: text('keyId').trim(),
            issuerId: text('issuerId').trim(),
            privateKey: text('privateKey'),
            kind: parsedKind,
          ),
        );
      case CredentialKind.appleId:
        return AppleIdMaterial(
          appleId: text('appleId').trim(),
          password: text('password').trim(),
        );
      case CredentialKind.playSa:
      case CredentialKind.firebaseSa:
        final json = text('serviceAccount');
        try {
          return ServiceAccountMaterial(
            kind,
            json: json,
            key: PlayServiceAccount.fromSecret(json),
          );
        } on FormatException catch (error) {
          throw CredentialRejectedException(
            error.message,
            fix:
                'Send the JSON key file of the service account as it came '
                'from Google Cloud (IAM, Service accounts, Keys).',
          );
        }
      case CredentialKind.keystore:
        final Uint8List bytes;
        try {
          bytes = base64.decode(
            base64.normalize(text('keystore').replaceAll(RegExp(r'\s'), '')),
          );
        } on FormatException {
          throw const CredentialRejectedException(
            'The keystore is not valid base64.',
            fix: 'Send the keystore file as base64 (base64 -i release.jks).',
          );
        }
        if (bytes.isEmpty) {
          throw const CredentialRejectedException('The keystore is empty.');
        }
        final storePassword = text('storePassword');
        return KeystoreMaterial(
          bytes: bytes,
          storePassword: storePassword,
          alias: text('keyAlias').trim(),
          keyPassword: optional('keyPassword') ?? storePassword,
        );
      case CredentialKind.shorebird:
      case CredentialKind.github:
        return TokenMaterial(kind, text('token').trim());
      case CredentialKind.slack:
        return SlackMaterial(text('webhookUrl').trim());
    }
  }

  /// Reads the secret of a credential back from [secrets].
  ///
  /// [secretKey] is the `secret_key` of the reference and [account] its
  /// `account`. Returns `null` if the secret is missing, or the label that
  /// completes it is.
  ///
  /// Throws a [SecretStoreException] if the secrets cannot be read and a
  /// [FormatException] if the stored secret is not what [kind] needs.
  static Future<CredentialMaterial?> load(
    CredentialKind kind,
    String secretKey,
    String? account,
    SecretStore secrets,
  ) async {
    switch (kind) {
      case CredentialKind.ascKey:
        final json = await secrets.read(secretKey);
        return json == null ? null : AscKeyMaterial(AscKey.fromSecret(json));
      case CredentialKind.appleId:
        final password = await secrets.read(secretKey);
        return password == null || account == null
            ? null
            : AppleIdMaterial(appleId: account, password: password);
      case CredentialKind.playSa:
      case CredentialKind.firebaseSa:
        final json = await secrets.read(secretKey);
        return json == null
            ? null
            : ServiceAccountMaterial(
                kind,
                json: json,
                key: PlayServiceAccount.fromSecret(json),
              );
      case CredentialKind.keystore:
        final bytes = await secrets.readBytes(secretKey);
        final storePassword = await secrets.read(
          KeystoreMaterial.storePasswordKey(secretKey),
        );
        final keyPassword = await secrets.read(
          KeystoreMaterial.keyPasswordKey(secretKey),
        );
        return bytes == null ||
                storePassword == null ||
                keyPassword == null ||
                account == null
            ? null
            : KeystoreMaterial(
                bytes: bytes,
                storePassword: storePassword,
                alias: account,
                keyPassword: keyPassword,
              );
      case CredentialKind.shorebird:
      case CredentialKind.github:
        final token = await secrets.read(secretKey);
        return token == null ? null : TokenMaterial(kind, token);
      case CredentialKind.slack:
        final url = await secrets.read(secretKey);
        return url == null ? null : SlackMaterial(url);
    }
  }

  /// Deletes the secret of a credential of [kind] under [secretKey].
  static Future<void> erase(
    CredentialKind kind,
    String secretKey,
    SecretStore secrets,
  ) async {
    await secrets.delete(secretKey);
    if (kind == CredentialKind.keystore) {
      await secrets.delete(KeystoreMaterial.storePasswordKey(secretKey));
      await secrets.delete(KeystoreMaterial.keyPasswordKey(secretKey));
    }
  }

  /// What the credential is for.
  CredentialKind get kind;

  /// Who it belongs to, when that is not secret: kept in the reference.
  String? get account;

  /// Every value that must never show up in a log.
  List<String> get secretValues;

  /// Stores the secret under [secretKey].
  Future<void> write(SecretStore secrets, String secretKey);
}

/// An App Store Connect API key.
final class AscKeyMaterial extends CredentialMaterial {
  /// Creates the material.
  const new(this.key);

  /// The key.
  final AscKey key;

  @override
  CredentialKind get kind => CredentialKind.ascKey;

  @override
  String get account => key.keyId;

  @override
  List<String> get secretValues => [key.privateKey, key.toSecret()];

  @override
  Future<void> write(SecretStore secrets, String secretKey) =>
      secrets.write(secretKey, key.toSecret());
}

/// An Apple ID and its app-specific password.
final class AppleIdMaterial extends CredentialMaterial {
  /// Creates the material.
  const new({required this.appleId, required this.password});

  /// The Apple ID, usually an email address.
  final String appleId;

  /// The app-specific password.
  final String password;

  @override
  CredentialKind get kind => CredentialKind.appleId;

  @override
  String get account => appleId;

  @override
  List<String> get secretValues => [password];

  @override
  Future<void> write(SecretStore secrets, String secretKey) =>
      secrets.write(secretKey, password);
}

/// A Google service account key file, for Google Play or Firebase.
final class ServiceAccountMaterial extends CredentialMaterial {
  /// Creates the material of [kind] (`play_sa` or `firebase_sa`).
  const new(this.kind, {required this.json, required this.key});

  /// The key file as it came.
  final String json;

  /// The key file read.
  final PlayServiceAccount key;

  @override
  final CredentialKind kind;

  @override
  String get account => key.clientEmail;

  @override
  List<String> get secretValues => [json, key.privateKey];

  @override
  Future<void> write(SecretStore secrets, String secretKey) =>
      secrets.write(secretKey, json);
}

/// An Android release keystore with its passwords.
final class KeystoreMaterial extends CredentialMaterial {
  /// Creates the material. [alias] is the key in the keystore.
  const new({
    required this.bytes,
    required this.storePassword,
    required this.alias,
    required this.keyPassword,
  });

  /// The secret key of the store password for a keystore under [secretKey].
  static String storePasswordKey(String secretKey) =>
      '$secretKey.storePassword';

  /// The secret key of the key password for a keystore under [secretKey].
  static String keyPasswordKey(String secretKey) => '$secretKey.keyPassword';

  /// The keystore file.
  final Uint8List bytes;

  /// The password of the keystore.
  final String storePassword;

  /// The alias of the signing key.
  final String alias;

  /// The password of the signing key.
  final String keyPassword;

  @override
  CredentialKind get kind => CredentialKind.keystore;

  @override
  String get account => alias;

  @override
  List<String> get secretValues => [storePassword, keyPassword];

  @override
  Future<void> write(SecretStore secrets, String secretKey) async {
    await secrets.writeBytes(secretKey, bytes);
    await secrets.write(storePasswordKey(secretKey), storePassword);
    await secrets.write(keyPasswordKey(secretKey), keyPassword);
  }
}

/// A token: a Shorebird API key or a GitHub token.
final class TokenMaterial extends CredentialMaterial {
  /// Creates the material of [kind] (`shorebird` or `github`).
  const new(this.kind, this.token);

  /// The token.
  final String token;

  @override
  final CredentialKind kind;

  @override
  String? get account => null;

  @override
  List<String> get secretValues => [token];

  @override
  Future<void> write(SecretStore secrets, String secretKey) =>
      secrets.write(secretKey, token);
}

/// A Slack incoming webhook. Whoever has the URL can post to the channel, so
/// it is a secret.
final class SlackMaterial extends CredentialMaterial {
  /// Creates the material.
  const new(this.webhookUrl);

  /// The webhook URL.
  final String webhookUrl;

  @override
  CredentialKind get kind => CredentialKind.slack;

  @override
  String? get account => null;

  @override
  List<String> get secretValues => [webhookUrl];

  @override
  Future<void> write(SecretStore secrets, String secretKey) =>
      secrets.write(secretKey, webhookUrl);
}
