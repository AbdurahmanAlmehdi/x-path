import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// A device token as the engine stores it: never the secret, only its hash.
class DeviceToken extends Equatable {
  /// Creates a stored token.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.hash,
    required this.createdAt,
    this.revokedAt,
  });

  /// Identifies the token without revealing it.
  final String id;

  /// What the owner calls the device or client, for example `Mac mini`.
  final String name;

  /// What the token is used by.
  final DeviceTokenKind kind;

  /// Hex SHA-256 of the secret.
  final String hash;

  /// When the token was issued, in UTC.
  final DateTime createdAt;

  /// When the token was revoked, in UTC, or `null` while it is valid.
  final DateTime? revokedAt;

  /// Whether the token no longer authenticates.
  bool get isRevoked => revokedAt != null;

  @override
  List<Object?> get props => [id, name, kind, hash, createdAt, revokedAt];
}
