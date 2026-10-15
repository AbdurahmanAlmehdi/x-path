import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/bloc/approval_subject.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// How long the confirmation sheet waits before ⌘↩ can approve, so a
/// keystroke meant for something else never approves (DECISIONS.md).
const approvalArmingDelay = Duration(seconds: 1);

sealed class ApprovalReviewEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the approval [approvalId].
final class ApprovalReviewStarted extends ApprovalReviewEvent {
  const new(this.approvalId);

  final String approvalId;

  @override
  List<Object?> get props => [approvalId];
}

/// Approves (⌘↩, once armed).
final class ApprovalReviewApproveRequested extends ApprovalReviewEvent {
  const new();
}

/// Denies, with an optional [reason].
final class ApprovalReviewDenyRequested extends ApprovalReviewEvent {
  const new({this.reason});

  final String? reason;

  @override
  List<Object?> get props => [reason];
}

final class _ApprovalReviewArmed extends ApprovalReviewEvent {
  const new();
}

final class _ApprovalReviewSubjectRequested extends ApprovalReviewEvent {
  const new(this.approval);

  final Approval approval;
}

enum ApprovalReviewStatus {
  /// The approval has not arrived yet.
  loading,

  /// It waits for the owner's decision.
  ready,

  /// The approval is on its way to the engine.
  approving,

  /// The denial is on its way to the engine.
  denying,

  /// This sheet approved it.
  approved,

  /// This sheet denied it.
  denied,

  /// It is not pending any more and this sheet did not decide it: another
  /// device decided first, or it expired.
  alreadyDecided,

  /// It cannot be read (for example it does not exist on this engine).
  failed,
}

class ApprovalReviewState extends Equatable {
  const new({
    this.status = ApprovalReviewStatus.loading,
    this.approval,
    this.subject = const ApprovalSubject(),
    this.armed = false,
    this.error,
  });

  final ApprovalReviewStatus status;
  final Approval? approval;
  final ApprovalSubject subject;

  /// Whether the arming delay is over.
  final bool armed;

  /// What the engine said when it could not be read or refused a decision.
  final String? error;

  /// Whether ⌘↩ approves now.
  bool get canApprove => armed && status == ApprovalReviewStatus.ready;

  /// Whether the owner may deny now.
  bool get canDeny => status == ApprovalReviewStatus.ready;

  ApprovalReviewState copyWith({
    ApprovalReviewStatus? status,
    Approval? approval,
    ApprovalSubject? subject,
    bool? armed,
    String? Function()? error,
  }) => ApprovalReviewState(
    status: status ?? this.status,
    approval: approval ?? this.approval,
    subject: subject ?? this.subject,
    armed: armed ?? this.armed,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [status, approval, subject, armed, error];
}

/// The confirmation sheet of one approval: the only place an approval is
/// decided in the app. Approve is armed [armingDelay] after the approval
/// shows; the first decision wins (D-13), so an approval another device
/// decided, or that expired, ends as [ApprovalReviewStatus.alreadyDecided].
class ApprovalReviewBloc
    extends Bloc<ApprovalReviewEvent, ApprovalReviewState> {
  new({
    required this._approvals,
    required this._jobs,
    required this._releases,
    this.armingDelay = approvalArmingDelay,
  }) : super(const ApprovalReviewState()) {
    on<ApprovalReviewStarted>(_onStarted, transformer: restartable());
    on<_ApprovalReviewSubjectRequested>(_onSubject);
    on<_ApprovalReviewArmed>(
      (event, emit) => emit(state.copyWith(armed: true)),
    );
    on<ApprovalReviewApproveRequested>(_onApprove, transformer: droppable());
    on<ApprovalReviewDenyRequested>(_onDeny, transformer: droppable());
  }

  final ApprovalsRepository _approvals;
  final JobsRepository _jobs;
  final ReleasesRepository _releases;

  /// How long approve waits after the approval shows.
  final Duration armingDelay;

  Timer? _arming;

  static const Set<ApprovalReviewStatus> _deciding = {
    ApprovalReviewStatus.approving,
    ApprovalReviewStatus.denying,
    ApprovalReviewStatus.approved,
    ApprovalReviewStatus.denied,
  };

  Future<void> _onStarted(
    ApprovalReviewStarted event,
    Emitter<ApprovalReviewState> emit,
  ) async {
    var asked = false;
    await emit.forEach<Snapshot<Approval>>(
      _approvals.watchApproval(event.approvalId),
      onData: (snapshot) {
        final approval = snapshot.value;
        if (!asked) {
          asked = true;
          add(_ApprovalReviewSubjectRequested(approval));
        }
        if (_deciding.contains(state.status)) {
          // This sheet decided; the call says how it ended.
          return state.copyWith(approval: approval);
        }
        if (approval.state.isSettled) {
          _arming?.cancel();
          return state.copyWith(
            status: ApprovalReviewStatus.alreadyDecided,
            approval: approval,
            error: () => null,
          );
        }
        _arming ??= Timer(armingDelay, () {
          if (!isClosed) add(const _ApprovalReviewArmed());
        });
        return state.copyWith(
          status: ApprovalReviewStatus.ready,
          approval: approval,
        );
      },
      onError: (error, _) => state.approval == null
          ? state.copyWith(
              status: ApprovalReviewStatus.failed,
              error: () => errorMessage(error),
            )
          : state,
    );
  }

  Future<void> _onSubject(
    _ApprovalReviewSubjectRequested event,
    Emitter<ApprovalReviewState> emit,
  ) async {
    final subject = await loadApprovalSubject(
      event.approval,
      jobs: _jobs,
      releases: _releases,
    );
    emit(state.copyWith(subject: subject));
  }

  Future<void> _onApprove(
    ApprovalReviewApproveRequested event,
    Emitter<ApprovalReviewState> emit,
  ) => _decide(
    emit,
    allowed: state.canApprove,
    during: ApprovalReviewStatus.approving,
    after: ApprovalReviewStatus.approved,
    decide: _approvals.approve,
  );

  Future<void> _onDeny(
    ApprovalReviewDenyRequested event,
    Emitter<ApprovalReviewState> emit,
  ) {
    final reason = event.reason?.trim();
    return _decide(
      emit,
      allowed: state.canDeny,
      during: ApprovalReviewStatus.denying,
      after: ApprovalReviewStatus.denied,
      decide: (id) => _approvals.deny(
        id,
        reason: reason == null || reason.isEmpty ? null : reason,
      ),
    );
  }

  Future<void> _decide(
    Emitter<ApprovalReviewState> emit, {
    required bool allowed,
    required ApprovalReviewStatus during,
    required ApprovalReviewStatus after,
    required Future<Approval> Function(String id) decide,
  }) async {
    final approval = state.approval;
    if (!allowed || approval == null) return;
    emit(state.copyWith(status: during, error: () => null));
    try {
      emit(state.copyWith(status: after, approval: await decide(approval.id)));
    } on ApprovalAlreadyDecided catch (error) {
      emit(
        state.copyWith(
          status: ApprovalReviewStatus.alreadyDecided,
          approval: error.approval,
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          status: ApprovalReviewStatus.ready,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _arming?.cancel();
    return super.close();
  }
}
