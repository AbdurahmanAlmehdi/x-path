import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/approvals/approval_record.dart';

/// Where approval requests are kept.
///
/// `xp_adapters` has the SQLite implementation. Every method that changes a
/// record is atomic: the engine relies on it for "first decision wins".
abstract interface class ApprovalRepository {
  /// The approval [id], or `null`.
  Future<ApprovalRecord?> get(String id);

  /// The approvals, newest first; only those of [projectId] and in [state] if
  /// given.
  Future<List<ApprovalRecord>> list({String? projectId, ApprovalState? state});

  /// Stores [candidate] unless a record with the same binding exists
  /// ([ApprovalRecord.hasSameBinding]), and returns the record that holds the
  /// binding and whether it is [candidate].
  Future<({ApprovalRecord record, bool created})> findOrCreate(
    ApprovalRecord candidate,
  );

  /// Compare-and-set: settles the approval [id] as [state] (`approved` or
  /// `denied`) if, and only if, it is still pending and its time is not up
  /// at [at]. Returns the settled record, or `null` if it was not pending, so
  /// that of two concurrent decisions exactly one gets a record.
  Future<ApprovalRecord?> decide(
    String id, {
    required ApprovalState state,
    required DecidedBy by,
    required DateTime at,
    String? reason,
  });

  /// Compare-and-set: settles the pending approvals whose time is up at [now]
  /// as `expired` with [reason], and returns those that this call settled.
  /// Only the approval [id] if given.
  Future<List<ApprovalRecord>> expireDue(
    DateTime now, {
    required String reason,
    String? id,
  });
}

/// An [ApprovalRepository] that forgets everything on exit.
class InMemoryApprovalRepository implements ApprovalRepository {
  final _records = <String, ApprovalRecord>{};

  @override
  Future<ApprovalRecord?> get(String id) async => _records[id];

  @override
  Future<List<ApprovalRecord>> list({
    String? projectId,
    ApprovalState? state,
  }) async => [
    for (final record in _records.values.toList().reversed)
      if ((projectId == null || record.projectId == projectId) &&
          (state == null || record.state == state))
        record,
  ];

  @override
  Future<({ApprovalRecord record, bool created})> findOrCreate(
    ApprovalRecord candidate,
  ) async {
    for (final record in _records.values) {
      if (record.hasSameBinding(candidate)) {
        return (record: record, created: false);
      }
    }
    _records[candidate.id] = candidate;
    return (record: candidate, created: true);
  }

  @override
  Future<ApprovalRecord?> decide(
    String id, {
    required ApprovalState state,
    required DecidedBy by,
    required DateTime at,
    String? reason,
  }) async {
    final record = _records[id];
    if (record == null ||
        record.state != ApprovalState.pending ||
        record.isDueAt(at)) {
      return null;
    }
    return _records[id] = record.settled(
      state: state,
      at: at,
      by: by,
      reason: reason,
    );
  }

  @override
  Future<List<ApprovalRecord>> expireDue(
    DateTime now, {
    required String reason,
    String? id,
  }) async => [
    for (final record in _records.values.toList())
      if ((id == null || record.id == id) && record.isDueAt(now))
        _records[record.id] = record.settled(
          state: ApprovalState.expired,
          at: now,
          reason: reason,
        ),
  ];
}
