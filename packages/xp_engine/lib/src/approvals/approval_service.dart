import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/approvals/approval_exceptions.dart';
import 'package:xp_engine/src/approvals/approval_record.dart';
import 'package:xp_engine/src/approvals/approval_repository.dart';
import 'package:xp_engine/src/approvals/gate_config.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/tokens/device_token.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';

/// How long an approval request waits for the owner. After this it expires,
/// which counts as denied (D-13).
const approvalLifetime = Duration(hours: 24);

/// Puts the jobs of the project [projectId] that wait for an approval back in
/// line, so that each asks again: `Scheduler.resumeWaiting`.
typedef ResumeWaiting = Future<void> Function(String projectId);

/// The approvals of gated actions (D-13), and the gates of projects.
///
/// **Asking.** A job that reaches a gate asks through [check] (this class is
/// the engine's [ApprovalGate]). The first ask for a project, action, commit,
/// version and run creates a pending request and announces it; every later
/// ask (the same job resumed, a sibling job of the matrix) finds the same
/// request. A different commit or version, or a new dispatch, is a new
/// request. A gate the project turned off approves at once and leaves no
/// request.
///
/// **Deciding.** Only an `app` or a `cli` token approves or denies. The
/// decision is one compare-and-set on `state = 'pending'` in the repository,
/// so of any number of concurrent decisions exactly one wins, and the others
/// learn the winner ([ApprovalAlreadyDecidedException]). The jobs that wait
/// are resumed, ask again and go on or fail.
///
/// **Expiring.** A request nobody decided within [approvalLifetime] turns
/// `expired`, and a job that asks about it is denied with that reason. This
/// happens lazily when a request is read and asked about, and in bulk by
/// [sweep], which the `ApprovalSweeper` calls every minute. A decided or
/// expired request is final for its run: to try again after a denial or an
/// expiry the owner dispatches the workflow again.
///
/// **Gates.** [setGates] turns the gate of an action on or off for a project.
/// An `app` token may do both; a `cli` token may only turn gates on
/// (tightening); `mcp` and `runner` tokens never change them.
class ApprovalService implements ApprovalGate {
  /// Creates the service. `resume` is told when a decision or a loosened gate
  /// lets waiting jobs go on.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._approvals,
    required this._gates,
    required this._projects,
    required this._jobs,
    required this._events,
    required this._clock,
    required this._resume,
    Random? random,
  }) : _random = random ?? Random.secure();

  final ApprovalRepository _approvals;
  final GateConfigRepository _gates;
  final ProjectRepository _projects;
  final JobRepository _jobs;
  final EventLog _events;
  final Clock _clock;
  final ResumeWaiting _resume;
  final Random _random;

  static const _expiredReason =
      'Nobody decided within 24 hours; an expired approval counts as denied.';

  // ---------------------------------------------------------------- asking

  @override
  Future<GateDecision> check(GateRequest request) async {
    final config = await _gates.get(request.projectId);
    if (!config.isGated(request.action)) return const GateApproved();
    final now = _clock.now();
    final job = await _jobs.get(request.jobId);
    final found = await _approvals.findOrCreate(
      ApprovalRecord(
        id: _newId(),
        projectId: request.projectId,
        action: request.action,
        sha: request.sha,
        version: request.version,
        runId: job?.runId,
        jobId: request.jobId,
        createdAt: now,
        expiresAt: now.add(approvalLifetime),
      ),
    );
    if (found.created) {
      final record = found.record;
      _events.append(
        ApprovalRequested(
          approvalId: record.id,
          projectId: record.projectId,
          action: record.action.wire,
          sha: record.sha,
          version: record.version,
          expiresAt: record.expiresAt,
        ),
      );
    }
    // The asking job is running: it must not resume itself.
    final record = await _settle(found.record, resume: false);
    return switch (record.state) {
      ApprovalState.pending => GatePending(approvalId: record.id),
      ApprovalState.approved => const GateApproved(),
      ApprovalState.denied => GateDenied(_deniedBecause(record)),
      ApprovalState.expired => GateDenied(
        'nobody approved it within 24 hours, so approval ${record.id} '
        'expired. Dispatch the workflow again to ask again.',
      ),
    };
  }

  static String _deniedBecause(ApprovalRecord record) {
    final by = record.decidedBy;
    final reason = record.reason;
    return 'denied${by == null ? '' : ' by ${by.name} (${by.kind.name})'}'
        '${reason == null ? '' : ': $reason'}.';
  }

  // --------------------------------------------------------------- reading

  /// The approvals, newest first; only those of the project [projectId] and in
  /// [state] if given. Requests whose time is up are expired first.
  Future<List<Approval>> list({String? projectId, ApprovalState? state}) async {
    await sweep();
    return [
      for (final record in await _approvals.list(
        projectId: projectId,
        state: state,
      ))
        record.toApi(),
    ];
  }

  /// The approval [id], expired first if its time is up.
  ///
  /// Throws an [ApprovalNotFoundException] if there is none.
  Future<Approval> get(String id) async => (await _require(id)).toApi();

  // -------------------------------------------------------------- deciding

  /// Approves the approval [id] if [approve], else denies it, as the device
  /// [by]. Returns the approval as decided.
  ///
  /// Throws an [ApprovalForbiddenException] unless [by] is an `app` or a
  /// `cli` token, an [ApprovalNotFoundException] if there is no such
  /// approval, and an [ApprovalAlreadyDecidedException] (with the winning
  /// decision) if it was decided or expired before.
  Future<Approval> decide(
    String id, {
    required bool approve,
    required DeviceToken by,
    String? reason,
  }) async {
    if (!_mayDecide(by.kind)) {
      throw ApprovalForbiddenException(
        'A ${by.kind.name} token cannot ${approve ? 'approve' : 'deny'}: only '
        'the app or `xp approve` decide gated actions.',
      );
    }
    final current = await _require(id);
    if (current.state.isSettled) {
      throw ApprovalAlreadyDecidedException(current.toApi());
    }
    final trimmed = reason?.trim();
    final decided = await _approvals.decide(
      id,
      state: approve ? ApprovalState.approved : ApprovalState.denied,
      by: DecidedBy(tokenId: by.id, name: by.name, kind: by.kind),
      at: _clock.now(),
      reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    if (decided == null) {
      // Someone decided between the read and the write: the first one won.
      throw ApprovalAlreadyDecidedException((await _require(id)).toApi());
    }
    _events.append(
      ApprovalDecided(
        approvalId: decided.id,
        projectId: decided.projectId,
        action: decided.action.wire,
        state: decided.state,
        decidedBy: decided.decidedBy!,
      ),
    );
    await _resume(decided.projectId);
    return decided.toApi();
  }

  // -------------------------------------------------------------- expiring

  /// Expires the requests whose time is up, announces each, and resumes the
  /// jobs that wait for them so that their gates fail. Returns how many
  /// expired.
  Future<int> sweep() async => (await _expire()).length;

  Future<List<ApprovalRecord>> _expire({String? id, bool resume = true}) async {
    final expired = await _approvals.expireDue(
      _clock.now(),
      reason: _expiredReason,
      id: id,
    );
    for (final record in expired) {
      _events.append(
        ApprovalExpired(
          approvalId: record.id,
          projectId: record.projectId,
          action: record.action.wire,
        ),
      );
    }
    if (resume) {
      for (final projectId in {for (final r in expired) r.projectId}) {
        await _resume(projectId);
      }
    }
    return expired;
  }

  Future<ApprovalRecord> _settle(
    ApprovalRecord record, {
    required bool resume,
  }) async {
    if (!record.isDueAt(_clock.now())) return record;
    final expired = await _expire(id: record.id, resume: resume);
    // Another sweep may have expired it first.
    return expired.firstOrNull ?? (await _approvals.get(record.id))!;
  }

  Future<ApprovalRecord> _require(String id) async {
    final record = await _approvals.get(id);
    if (record == null) throw ApprovalNotFoundException(id);
    return await _settle(record, resume: true);
  }

  // ----------------------------------------------------------------- gates

  /// Which actions of the project [projectId] wait for an approval: every
  /// action.
  ///
  /// Throws a [ProjectNotFoundException] if there is no such project.
  Future<ProjectGates> gates(String projectId) async {
    await _requireProject(projectId);
    return (await _gates.get(projectId)).toApi();
  }

  /// Replaces the gates of the project [projectId] with [desired], as the
  /// device [by]; an action that [desired] leaves out is gated. Returns the
  /// gates now.
  ///
  /// Turning a gate off loosens it, and lets the jobs that wait at it go on.
  ///
  /// Throws an [ApprovalForbiddenException] unless [by] is an `app` token, or
  /// a `cli` token that only tightens; a [ProjectNotFoundException]; and an
  /// [ApprovalRequestException] for an action that is not a gate.
  Future<ProjectGates> setGates(
    String projectId,
    ProjectGates desired, {
    required DeviceToken by,
  }) async {
    if (!_mayDecide(by.kind)) {
      throw ApprovalForbiddenException(
        'A ${by.kind.name} token cannot change gates: only the app or '
        '`xp` do.',
      );
    }
    await _requireProject(projectId);
    final next = GateConfig.fromApi(desired);
    final current = await _gates.get(projectId);
    final loosened = current.loosenedBy(next);
    if (loosened.isNotEmpty && by.kind != DeviceTokenKind.app) {
      throw ApprovalForbiddenException(
        'A ${by.kind.name} token can turn gates on but not off. Turn off '
        '${loosened.map((action) => action.wire).join(', ')} in the app.',
      );
    }
    if (next == current) return current.toApi();
    await _gates.set(projectId, next);
    final applied = next.toApi();
    _events.append(
      ProjectGatesChanged(
        projectId: projectId,
        gates: applied.gates,
        changedBy: by.kind,
      ),
    );
    if (loosened.isNotEmpty) await _resume(projectId);
    return applied;
  }

  // --------------------------------------------------------------- helpers

  static bool _mayDecide(DeviceTokenKind kind) =>
      kind == DeviceTokenKind.app || kind == DeviceTokenKind.cli;

  Future<void> _requireProject(String projectId) async {
    if (await _projects.get(projectId) == null) {
      throw ProjectNotFoundException(projectId);
    }
  }

  String _newId() {
    final hex = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    );
    return 'apr_${hex.join()}';
  }
}
