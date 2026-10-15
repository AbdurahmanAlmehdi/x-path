import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/bloc/approval_subject.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The filters of the inbox.
enum ApprovalsFilter {
  pending,
  decided,
  expired;

  /// The filter an approval in [state] is listed under.
  static ApprovalsFilter of(ApprovalState state) => switch (state) {
    ApprovalState.pending => pending,
    ApprovalState.approved || ApprovalState.denied => decided,
    ApprovalState.expired => expired,
  };
}

sealed class ApprovalsInboxEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following every approval of the engine, showing [approvalId]
/// first if given.
final class ApprovalsInboxSubscriptionRequested extends ApprovalsInboxEvent {
  const new({this.approvalId});

  final String? approvalId;

  @override
  List<Object?> get props => [approvalId];
}

/// Lists the approvals under [filter].
final class ApprovalsInboxFilterChanged extends ApprovalsInboxEvent {
  const new(this.filter);

  final ApprovalsFilter filter;

  @override
  List<Object?> get props => [filter];
}

/// Shows [approvalId] in the detail pane.
final class ApprovalsInboxApprovalSelected extends ApprovalsInboxEvent {
  const new(this.approvalId);

  final String approvalId;

  @override
  List<Object?> get props => [approvalId];
}

final class _ApprovalsInboxSubjectRequested extends ApprovalsInboxEvent {
  const new(this.approval);

  final Approval approval;
}

class ApprovalsInboxState extends Equatable {
  const new({
    this.loaded = false,
    this.approvals = const [],
    this.cached = false,
    this.filter = ApprovalsFilter.pending,
    this.selectedId,
    this.subject = const ApprovalSubject(),
    this.error,
  });

  final bool loaded;

  /// Every approval of the engine, newest first.
  final List<Approval> approvals;

  /// Whether [approvals] came from the offline cache.
  final bool cached;
  final ApprovalsFilter filter;
  final String? selectedId;

  /// The job and release of [selected].
  final ApprovalSubject subject;

  /// What the engine said when it could not be read.
  final String? error;

  /// The approvals under [filter].
  List<Approval> get visible => [
    for (final approval in approvals)
      if (ApprovalsFilter.of(approval.state) == filter) approval,
  ];

  /// How many approvals wait.
  int get pendingCount =>
      approvals.where((a) => a.state == ApprovalState.pending).length;

  /// The approval in the detail pane: the one picked, else the first under
  /// [filter].
  Approval? get selected {
    final visible = this.visible;
    for (final approval in visible) {
      if (approval.id == selectedId) return approval;
    }
    return visible.firstOrNull;
  }

  ApprovalsInboxState copyWith({
    bool? loaded,
    List<Approval>? approvals,
    bool? cached,
    ApprovalsFilter? filter,
    String? Function()? selectedId,
    ApprovalSubject? subject,
    String? Function()? error,
  }) => ApprovalsInboxState(
    loaded: loaded ?? this.loaded,
    approvals: approvals ?? this.approvals,
    cached: cached ?? this.cached,
    filter: filter ?? this.filter,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    subject: subject ?? this.subject,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    loaded,
    approvals,
    cached,
    filter,
    selectedId,
    subject,
    error,
  ];
}

/// The approvals inbox (`Approvals-Inbox.dc.html`): every approval of the
/// engine under Pending, Decided and Expired, and the one picked with its
/// job and release. Deciding happens in the confirmation sheet.
class ApprovalsInboxBloc
    extends Bloc<ApprovalsInboxEvent, ApprovalsInboxState> {
  new({required this._approvals, required this._jobs, required this._releases})
    : super(const ApprovalsInboxState()) {
    on<ApprovalsInboxSubscriptionRequested>(
      _onSubscribe,
      transformer: restartable(),
    );
    on<ApprovalsInboxFilterChanged>(
      (event, emit) => _show(
        emit,
        state.copyWith(filter: event.filter, selectedId: () => null),
      ),
    );
    on<ApprovalsInboxApprovalSelected>(
      (event, emit) =>
          _show(emit, state.copyWith(selectedId: () => event.approvalId)),
    );
    on<_ApprovalsInboxSubjectRequested>(_onSubject, transformer: restartable());
  }

  final ApprovalsRepository _approvals;
  final JobsRepository _jobs;
  final ReleasesRepository _releases;
  String? _subjectOf;

  /// Emits [next], and reads the job and release of its selected approval
  /// when that changed.
  void _show(Emitter<ApprovalsInboxState> emit, ApprovalsInboxState next) {
    final selected = next.selected;
    final changed = selected?.id != _subjectOf;
    emit(changed ? next.copyWith(subject: const ApprovalSubject()) : next);
    if (changed) {
      _subjectOf = selected?.id;
      if (selected != null) add(_ApprovalsInboxSubjectRequested(selected));
    }
  }

  Future<void> _onSubscribe(
    ApprovalsInboxSubscriptionRequested event,
    Emitter<ApprovalsInboxState> emit,
  ) async {
    var focus = event.approvalId;
    await emit.forEach<Snapshot<List<Approval>>>(
      _approvals.watchApprovals(),
      onData: (snapshot) {
        var next = state.copyWith(
          loaded: true,
          approvals: snapshot.value,
          cached: snapshot.cached,
          error: () => null,
        );
        final focused = snapshot.value.where((a) => a.id == focus).firstOrNull;
        if (focused != null) {
          focus = null;
          next = next.copyWith(
            filter: ApprovalsFilter.of(focused.state),
            selectedId: () => focused.id,
          );
        }
        _show(emit, next);
        return state;
      },
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
  }

  Future<void> _onSubject(
    _ApprovalsInboxSubjectRequested event,
    Emitter<ApprovalsInboxState> emit,
  ) async {
    final subject = await loadApprovalSubject(
      event.approval,
      jobs: _jobs,
      releases: _releases,
    );
    if (state.selected?.id == event.approval.id) {
      emit(state.copyWith(subject: subject));
    }
  }
}
