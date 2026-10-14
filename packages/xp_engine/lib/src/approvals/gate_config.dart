import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/approvals/approval_exceptions.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';

/// Which actions of a project wait for the owner's approval (D-13).
///
/// Every action is gated unless the project turned its gate off, so a project
/// that never set anything is as safe as can be. Turning a gate off is
/// loosening; only an `app` token may do it.
class GateConfig extends Equatable {
  /// Creates the configuration of the given actions; the others are gated.
  const new([this._gated = const {}]);

  /// Reads the stored form, `{"push": false}`. Anything it does not know is
  /// ignored, so an older engine reads what a newer one wrote.
  factory fromJson(Map<String, dynamic> json) => GateConfig({
    for (final entry in json.entries)
      if (GateAction.fromWire(entry.key) case final action?)
        if (entry.value case final bool value) action: value,
  });

  /// Reads the API form.
  ///
  /// Throws an `ApprovalRequestException` for an action that is not a gate.
  factory fromApi(ProjectGates gates) {
    final configured = <GateAction, bool>{};
    for (final entry in gates.gates.entries) {
      final action = GateAction.fromWire(entry.key);
      if (action == null) {
        throw ApprovalRequestException(
          '"${entry.key}" is not a gate. The gates are: '
          '${GateAction.values.map((action) => action.wire).join(', ')}.',
        );
      }
      configured[action] = entry.value;
    }
    return GateConfig(configured);
  }

  final Map<GateAction, bool> _gated;

  /// Whether [action] waits for an approval.
  bool isGated(GateAction action) => _gated[action] ?? true;

  /// The actions that are gated here and not in [next]: what moving to [next]
  /// loosens.
  List<GateAction> loosenedBy(GateConfig next) => [
    for (final action in GateAction.values)
      if (isGated(action) && !next.isGated(action)) action,
  ];

  /// The stored form: every action.
  Map<String, dynamic> toJson() => {
    for (final action in GateAction.values) action.wire: isGated(action),
  };

  /// The API form: every action.
  ProjectGates toApi() => ProjectGates({
    for (final action in GateAction.values) action.wire: isGated(action),
  });

  @override
  List<Object?> get props => [
    for (final action in GateAction.values) isGated(action),
  ];
}

/// Where the gates of projects are kept (`project.gates`).
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class GateConfigRepository {
  /// The gates of the project [projectId]. A project that never set any, or
  /// that does not exist, has every gate on.
  Future<GateConfig> get(String projectId);

  /// Stores the gates of the project [projectId].
  Future<void> set(String projectId, GateConfig config);
}

/// A [GateConfigRepository] that forgets everything on exit.
class InMemoryGateConfigRepository implements GateConfigRepository {
  final _configs = <String, GateConfig>{};

  @override
  Future<GateConfig> get(String projectId) async =>
      _configs[projectId] ?? const GateConfig();

  @override
  Future<void> set(String projectId, GateConfig config) async =>
      _configs[projectId] = config;
}
