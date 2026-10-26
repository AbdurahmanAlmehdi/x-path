import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/releases/widgets/release_labels.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// One line of the timeline of a release.
class TimelineEntry extends Equatable {
  const new({
    required this.status,
    required this.title,
    required this.at,
    this.detail,
  });

  final XpStatus status;
  final String title;
  final String? detail;
  final DateTime at;

  @override
  List<Object?> get props => [status, title, detail, at];
}

/// What happened to [release], newest first: its [history] (U7b) and the
/// approvals of its runs. A release from before the engine kept a history
/// shows what the release itself keeps: its dispatch and builds, the last
/// change in each store and its end.
List<TimelineEntry> releaseTimeline(
  Release release,
  List<Approval> approvals,
  AppLocalizations l10n, {
  List<ReleaseEvent> history = const [],
}) {
  final runs = {
    for (final build in release.builds) build.runId,
    ?release.mergeRunId,
    for (final event in history) ?event.runId,
  };
  final approvalEntries = [
    for (final approval in approvals)
      if (runs.contains(approval.runId)) ...[
        TimelineEntry(
          status: XpStatus.approvalPending,
          title: l10n.timelineApprovalAsked(l10n.approvalTitle(approval)),
          detail: shortSha(approval.sha),
          at: approval.createdAt,
        ),
        if (approval.state.isSettled)
          TimelineEntry(
            status: approvalStatus(approval.state),
            title: l10n.timelineApprovalSettled(
              l10n.approvalTitle(approval),
              l10n.approvalState(approval.state).toLowerCase(),
            ),
            detail: approval.decidedBy?.name ?? approval.reason,
            at: approval.decidedAt ?? approval.expiresAt,
          ),
      ],
  ];
  if (history.isNotEmpty) {
    return _newestFirst([
      for (final event in history) _entryOf(release, event, l10n),
      ...approvalEntries,
    ]);
  }
  final entries = <TimelineEntry>[
    TimelineEntry(
      status: XpStatus.releaseDraft,
      title: l10n.timelineDispatched,
      detail: release.flavor,
      at: release.createdAt,
    ),
    for (final build in release.builds)
      TimelineEntry(
        status: XpStatus.releaseBuilding,
        title: l10n.timelineBuild(build.build.toString()),
        at: build.createdAt,
      ),
    for (final status in release.stores)
      if (status.changedAt case final changed?)
        TimelineEntry(
          status: storeStatus(status.store, status.state),
          title: l10n.timelineStore(
            l10n.storeName(status.store),
            l10n.storeState(status.store, status.state).toLowerCase(),
          ),
          detail: l10n.statusSource(status.store, status.source),
          at: changed,
        ),
    ...approvalEntries,
    if (release.state == ReleaseState.merged)
      TimelineEntry(
        status: XpStatus.releaseMerged,
        title: l10n.timelineMerged(
          release.baseBranch ?? l10n.approvalBaseBranch,
        ),
        detail: release.mergeCommit == null
            ? null
            : shortSha(release.mergeCommit!),
        at: release.updatedAt,
      ),
    if (release.state == ReleaseState.abandoned)
      TimelineEntry(
        status: XpStatus.releaseAbandoned,
        title: l10n.releaseAbandoned,
        detail: release.message,
        at: release.updatedAt,
      ),
  ];
  return _newestFirst(entries);
}

/// [entries] newest first; of two at the same time, the one later in
/// [entries] (a build after its dispatch) first.
List<TimelineEntry> _newestFirst(List<TimelineEntry> entries) {
  final order = {for (final (index, entry) in entries.indexed) entry: index};
  return entries..sort((a, b) {
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : order[b]!.compareTo(order[a]!);
  });
}

/// The line of [event] of the history of [release].
TimelineEntry _entryOf(
  Release release,
  ReleaseEvent event,
  AppLocalizations l10n,
) {
  final number = event.patchNumber ?? 0;
  final store = event.store;
  final (status, title, detail) = switch (event.kind) {
    ReleaseEventKind.created => (
      XpStatus.releaseDraft,
      l10n.timelineDispatched,
      release.flavor,
    ),
    ReleaseEventKind.build => (
      XpStatus.releaseBuilding,
      l10n.timelineBuild(event.detail ?? ''),
      null,
    ),
    ReleaseEventKind.store => _storeLine(store!, event.detail, l10n),
    ReleaseEventKind.mergeRequested => (
      XpStatus.approvalPending,
      l10n.timelineMergeRequested,
      null,
    ),
    ReleaseEventKind.merged => (
      XpStatus.releaseMerged,
      l10n.timelineMerged(release.baseBranch ?? l10n.approvalBaseBranch),
      event.detail == null ? null : shortSha(event.detail!),
    ),
    ReleaseEventKind.abandoned => (
      XpStatus.releaseAbandoned,
      l10n.releaseAbandoned,
      event.detail,
    ),
    ReleaseEventKind.rolloutRequested => (
      XpStatus.approvalPending,
      l10n.timelineRolloutRequested,
      null,
    ),
    ReleaseEventKind.rollout => (
      XpStatus.releaseLive,
      l10n.timelineRollout(store == null ? '' : l10n.storeName(store)),
      event.detail,
    ),
    ReleaseEventKind.patch => (
      XpStatus.releaseLive,
      l10n.timelinePatch(number),
      event.detail,
    ),
    ReleaseEventKind.patchRequested => (
      XpStatus.approvalPending,
      event.detail == PatchAction.rollback.wire
          ? l10n.timelinePatchRollbackRequested(number)
          : l10n.timelinePatchPromoteRequested(number),
      null,
    ),
    ReleaseEventKind.patchPromoted => (
      XpStatus.releaseLive,
      l10n.timelinePatchPromoted(number),
      null,
    ),
    ReleaseEventKind.patchRolledBack => (
      XpStatus.releaseRejected,
      l10n.timelinePatchRolledBack(number),
      null,
    ),
    ReleaseEventKind.texts => (XpStatus.releaseDraft, l10n.timelineTexts, null),
  };
  return TimelineEntry(
    status: status,
    title: title,
    detail: [?detail, ?event.by].join(' · ').ifEmpty,
    at: event.at,
  );
}

/// The status and title of a change of [store] to the state named [wire].
(XpStatus, String, String?) _storeLine(
  ReleaseStore store,
  String? wire,
  AppLocalizations l10n,
) {
  final state = StoreState.values.where((s) => s.wire == wire).firstOrNull;
  if (state == null) {
    return (
      XpStatus.releaseDraft,
      l10n.timelineStore(l10n.storeName(store), wire ?? ''),
      null,
    );
  }
  return (
    storeStatus(store, state),
    l10n.timelineStore(
      l10n.storeName(store),
      l10n.storeState(store, state).toLowerCase(),
    ),
    null,
  );
}

extension on String {
  /// This text, or `null` when it is empty.
  String? get ifEmpty => isEmpty ? null : this;
}

/// The timeline panel of a release, newest first.
class ReleaseTimeline extends StatelessWidget {
  const new({
    required this.release,
    required this.approvals,
    this.history = const [],
    super.key,
  });

  final Release release;
  final List<Approval> approvals;

  /// What happened to [release], oldest first.
  final List<ReleaseEvent> history;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final entries = releaseTimeline(release, approvals, l10n, history: history);
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              XpSectionLabel(l10n.timelineTitle),
              const Spacer(),
              Text(
                l10n.timelineNewestFirst,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: XpStatusIcon(entry.status),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: type.body.copyWith(color: colors.textPrimary),
                        ),
                        if (entry.detail case final detail?)
                          Text(
                            detail,
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatDateTime(entry.at),
                    style: type.code.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
