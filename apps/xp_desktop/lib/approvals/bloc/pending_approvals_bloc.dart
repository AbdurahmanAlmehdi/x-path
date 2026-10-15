import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class PendingApprovalsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the approvals of the engine that wait for a decision.
final class PendingApprovalsSubscriptionRequested
    extends PendingApprovalsEvent {
  const new();
}

class PendingApprovalsState extends Equatable {
  const new({
    this.loaded = false,
    this.approvals = const [],
    this.cached = false,
  });

  /// Whether the approvals arrived (from the cache or the engine).
  final bool loaded;

  /// The approvals that wait, newest first.
  final List<Approval> approvals;

  /// Whether [approvals] came from the offline cache.
  final bool cached;

  /// The approvals of [projectId] that wait, the one that expires first
  /// first: what the needs-you bar of the project shows.
  List<Approval> of(String projectId) => [
    for (final approval in approvals)
      if (approval.projectId == projectId) approval,
  ]..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));

  @override
  List<Object?> get props => [loaded, approvals, cached];
}

/// The approvals of the engine that wait (D-13): the needs-you bar, the
/// count in the sidebar, the notifications and the menu bar extra.
class PendingApprovalsBloc
    extends Bloc<PendingApprovalsEvent, PendingApprovalsState> {
  new({required this._approvals}) : super(const PendingApprovalsState()) {
    on<PendingApprovalsSubscriptionRequested>(
      (event, emit) => emit.forEach<Snapshot<List<Approval>>>(
        _approvals.watchApprovals(state: ApprovalState.pending),
        onData: (snapshot) => PendingApprovalsState(
          loaded: true,
          approvals: [
            for (final approval in snapshot.value)
              if (approval.state == ApprovalState.pending) approval,
          ],
          cached: snapshot.cached,
        ),
        // The connection banner says why; what was shown stays.
        onError: (_, _) => state,
      ),
      transformer: restartable(),
    );
  }

  final ApprovalsRepository _approvals;
}
