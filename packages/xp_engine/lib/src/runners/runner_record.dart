import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scheduler/capability.dart';

const _unset = Object();

/// What the engine stores about a runner (D-08).
///
/// The credential of the runner is a device token of kind `runner`
/// ([tokenId]); only its hash is stored, with the token.
class RunnerRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.name,
    required this.tokenId,
    required this.createdAt,
    this.capabilities = const {},
    this.slots = 1,
    this.os,
    this.arch,
    this.version,
    this.cores,
    this.lastHeartbeat,
    this.revokedAt,
  });

  /// The engine's id, for example `rnr_1a2b3c4d5e6f7a8b`.
  final String id;

  /// What the owner called it. Unique.
  final String name;

  /// The device token that is its credential.
  final String tokenId;

  /// What the engine's probe found it can do at its last connection (D-19).
  /// Empty until the first probe.
  final Set<Capability> capabilities;

  /// How many jobs it runs at once.
  final int slots;

  /// The operating system it reported.
  final String? os;

  /// The architecture it reported.
  final String? arch;

  /// The `xp` version it reported.
  final String? version;

  /// The processor cores it reported.
  final int? cores;

  /// When the engine last heard from it.
  final DateTime? lastHeartbeat;

  /// When it was paired.
  final DateTime createdAt;

  /// When it was revoked, or `null`.
  final DateTime? revokedAt;

  /// Whether the owner revoked it.
  bool get isRevoked => revokedAt != null;

  /// This record with the given fields replaced.
  RunnerRecord copyWith({
    Set<Capability>? capabilities,
    int? slots,
    Object? os = _unset,
    Object? arch = _unset,
    Object? version = _unset,
    Object? cores = _unset,
    Object? lastHeartbeat = _unset,
    Object? revokedAt = _unset,
  }) => RunnerRecord(
    id: id,
    name: name,
    tokenId: tokenId,
    createdAt: createdAt,
    capabilities: capabilities ?? this.capabilities,
    slots: slots ?? this.slots,
    os: identical(os, _unset) ? this.os : os as String?,
    arch: identical(arch, _unset) ? this.arch : arch as String?,
    version: identical(version, _unset) ? this.version : version as String?,
    cores: identical(cores, _unset) ? this.cores : cores as int?,
    lastHeartbeat: identical(lastHeartbeat, _unset)
        ? this.lastHeartbeat
        : lastHeartbeat as DateTime?,
    revokedAt: identical(revokedAt, _unset)
        ? this.revokedAt
        : revokedAt as DateTime?,
  );

  /// The API form, for a runner that is [status] and holds the leases of
  /// [jobIds].
  Runner toRunner({
    required RunnerStatus status,
    List<String> jobIds = const [],
  }) => Runner(
    id: id,
    name: name,
    status: status,
    capabilities: wireNames(capabilities),
    slots: slots,
    jobIds: jobIds,
    os: os,
    arch: arch,
    version: version,
    cores: cores,
    lastHeartbeat: lastHeartbeat,
    createdAt: createdAt,
    revokedAt: revokedAt,
  );

  /// The wire names of [capabilities], sorted.
  static List<String> wireNames(Set<Capability> capabilities) =>
      [for (final capability in capabilities) capability.wire]..sort();

  @override
  List<Object?> get props => [
    id,
    name,
    tokenId,
    capabilities,
    slots,
    os,
    arch,
    version,
    cores,
    lastHeartbeat,
    createdAt,
    revokedAt,
  ];
}
