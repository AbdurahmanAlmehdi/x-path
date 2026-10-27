import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scheduler/capability.dart';

/// A runner paired with the engine, as the scheduler names it when a job
/// waits for a capability no connected runner has.
class PairedRunner extends Equatable {
  /// Creates the runner.
  const new({
    required this.id,
    required this.name,
    required this.capabilities,
    required this.connected,
    this.lastSeen,
    this.missing = const [],
  });

  /// The runner's id.
  final String id;

  /// Its name.
  final String name;

  /// What its last probe found.
  final Set<Capability> capabilities;

  /// Whether it has a connection open, probed or not.
  final bool connected;

  /// When the engine last heard from it.
  final DateTime? lastSeen;

  /// What its probe on this connection found missing, and the fixes; empty
  /// while it is not connected or not probed yet.
  final List<MissingCapability> missing;

  @override
  List<Object?> get props => [
    id,
    name,
    capabilities,
    connected,
    lastSeen,
    missing,
  ];
}

/// The runners paired with the engine, revoked ones left out: what the
/// scheduler asks to say which offline runner could take a waiting job. The
/// runners hub has them.
abstract interface class PairedRunners {
  /// Every paired runner that is not revoked.
  Future<List<PairedRunner>> pairedRunners();
}
