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

/// What happened to [release], newest first, from what the engine keeps:
/// its dispatch and builds, the last change in each store, the approvals of
/// its runs and its end.
List<TimelineEntry> releaseTimeline(
  Release release,
  List<Approval> approvals,
  AppLocalizations l10n,
) {
  final runs = {
    for (final build in release.builds) build.runId,
    ?release.mergeRunId,
  };
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
  // Newest first; of two at the same time, the one that happened later in
  // the list above (a build after its dispatch) first.
  final order = {for (final (index, entry) in entries.indexed) entry: index};
  return entries..sort((a, b) {
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : order[b]!.compareTo(order[a]!);
  });
}

/// The timeline panel of a release, newest first.
class ReleaseTimeline extends StatelessWidget {
  const new({required this.release, required this.approvals, super.key});

  final Release release;
  final List<Approval> approvals;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final entries = releaseTimeline(release, approvals, l10n);
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
