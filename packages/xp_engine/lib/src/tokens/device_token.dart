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
    this.personId,
    this.person,
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

  /// The person the token belongs to. `null` only for a runner token
  /// (ADR 0017).
  final String? personId;

  /// The person [personId] names, as they are now: the `TokenService` reads
  /// them with the token, so a new role applies to the next request. `null`
  /// when the token was not read for a request, and for a runner token.
  final Person? person;

  /// What [person] may do, or `null` without one.
  PersonRole? get role => person?.role;

  /// Whether the token no longer authenticates.
  bool get isRevoked => revokedAt != null;

  /// Who a run this token starts was started by (ADR 0017): an `mcp` token
  /// is an agent acting for its [person], any other token its [person].
  /// `null` without a [person] read, as for a runner token.
  RunOrigin? get runOrigin {
    final person = this.person;
    if (person == null) return null;
    return RunOrigin(
      kind: kind == DeviceTokenKind.mcp
          ? RunOriginKind.agent
          : RunOriginKind.person,
      tokenId: id,
      personId: person.id,
      personName: person.name,
    );
  }

  /// This token as revoked at [at].
  DeviceToken revoked(DateTime at) => _copy(revokedAt: at, person: person);

  /// This token with its [person] read.
  DeviceToken withPerson(Person person) =>
      _copy(revokedAt: revokedAt, person: person);

  DeviceToken _copy({required DateTime? revokedAt, required Person? person}) =>
      DeviceToken(
        id: id,
        name: name,
        kind: kind,
        hash: hash,
        createdAt: createdAt,
        revokedAt: revokedAt,
        personId: personId,
        person: person,
      );

  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    hash,
    createdAt,
    revokedAt,
    personId,
    person,
  ];
}
