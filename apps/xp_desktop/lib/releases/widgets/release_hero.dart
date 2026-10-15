import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/releases/bloc/release_board_bloc.dart';
import 'package:xp_desktop/releases/widgets/release_labels.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Why Merge is not open for [release], or what it merges when it is
/// (`Release-A-*.dc.html`: the Merge button says why it sleeps).
String mergeCaption(
  Release release,
  ReleaseBoardState board,
  AppLocalizations l10n,
) {
  final branch = release.branch;
  final base = release.baseBranch ?? l10n.approvalBaseBranch;
  if (release.state == ReleaseState.merged) {
    return l10n.mergeDone(shortSha(release.mergeCommit ?? ''));
  }
  if (release.state == ReleaseState.abandoned) return l10n.mergeAbandoned;
  if (release.mergeEnabled) {
    return branch == null
        ? l10n.mergeReady
        : l10n.mergeReadyBranch(branch, base);
  }
  if (release.mergeRunId != null) {
    final waits = board.approvals.any(
      (approval) =>
          approval.runId == release.mergeRunId &&
          approval.state == ApprovalState.pending,
    );
    return waits ? l10n.mergeWaitsApproval : l10n.mergeRequested;
  }
  final rejected = storesIn(release, StoreState.rejected);
  if (rejected.isNotEmpty) return l10n.mergeRejected(l10n.storeList(rejected));
  final notLive = [
    for (final status in release.stores)
      if (status.state != StoreState.live) status.store,
  ];
  if (notLive.isEmpty) {
    return release.prNumber == null ? l10n.mergeNoPr : l10n.mergeReady;
  }
  final marks = [
    for (final store in notLive)
      if (!board.readsStore(release, store)) store,
  ];
  if (marks.isEmpty) {
    return notLive.length > 1
        ? l10n.mergeWaitsBoth
        : l10n.mergeWaitsStore(l10n.storeName(notLive.single));
  }
  String part(ReleaseStore store) => marks.contains(store)
      ? l10n.mergeMark(l10n.storeName(store))
      : l10n.mergeMust(l10n.storeName(store));
  return notLive.map(part).join(l10n.listAnd);
}

/// The hero of a release: its state, version, commit, tag and branch, and
/// the Merge button with why it is not open yet.
class ReleaseHero extends StatelessWidget {
  const new({required this.release, super.key});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final board = context.watch<ReleaseBoardBloc>().state;
    final status = heroStatus(release);
    final canCommand = context.canCommand;
    final base = release.baseBranch ?? l10n.approvalBaseBranch;
    final meta = type.caption.copyWith(color: colors.textSecondary);
    final code = type.code.copyWith(color: colors.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  XpStatusIcon(status, size: context.xpSizes.iconLg),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      l10n.releaseHero(release),
                      overflow: TextOverflow.ellipsis,
                      style: type.hero.copyWith(
                        color: colors.onContainer(status.pair),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    versionLabel(release.version, release.build),
                    style: type.heroCode.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(release.flavor, style: meta),
                  if (release.headSha case final sha?) ...[
                    Text('·', style: meta),
                    Tooltip(
                      message: sha,
                      child: Text(shortSha(sha), style: code),
                    ),
                  ],
                  if (release.tag case final tag?) ...[
                    Text('·', style: meta),
                    Text(tag, style: code),
                  ],
                  if (release.branch case final branch?) ...[
                    Text('·', style: meta),
                    Text(branch, style: code),
                    Text('→ $base', style: meta),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (release.state != ReleaseState.merged)
              XpButton(
                label: l10n.mergeInto(base),
                kind: XpButtonKind.primary,
                size: XpButtonSize.large,
                icon: PhosphorIconsRegular.gitMerge,
                busy: board.command == ReleaseCommand.merging,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed:
                    release.mergeEnabled &&
                        canCommand &&
                        board.command == ReleaseCommand.none
                    ? () => context.read<ReleaseBoardBloc>().add(
                        const ReleaseBoardMergeRequested(),
                      )
                    : null,
              ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                mergeCaption(release, board, l10n),
                textAlign: TextAlign.end,
                style: meta,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
