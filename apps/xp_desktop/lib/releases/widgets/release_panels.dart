import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/releases/bloc/release_board_bloc.dart';
import 'package:xp_desktop/releases/widgets/release_labels.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The release notes from the commits since the release before, with the
/// text for Slack and WhatsApp one click away.
class ReleaseNotesPanel extends StatelessWidget {
  const new({required this.release, super.key});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final board = context.watch<ReleaseBoardBloc>().state;
    final notes = board.notes;
    final body = type.body.copyWith(color: colors.textPrimary);
    final caption = type.caption.copyWith(color: colors.textSecondary);
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              XpSectionLabel(l10n.notesTitle),
              const SizedBox(width: 8),
              if (notes != null)
                Expanded(
                  child: Text(
                    notes.from == null
                        ? l10n.notesCommits(notes.commits)
                        : l10n.notesSince(notes.from!, notes.commits),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: caption,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (release.headSha == null)
            Text(l10n.notesUntagged, style: caption)
          else if (board.notesError case final error?)
            XpMessage(XpStatus.scanWarning, error)
          else if (notes == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: XpStatusIcon(XpStatus.jobRunning),
            )
          else ...[
            if (notes.groups.isEmpty) Text(l10n.notesNothing, style: caption),
            for (final group in notes.groups) ...[
              Text(
                group.title,
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 2),
              for (final item in group.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '•  ${[?item.scope, item.description].join(': ')}',
                    style: body,
                  ),
                ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CopyButton(label: l10n.notesCopySlack, text: notes.slack),
                CopyButton(label: l10n.notesCopyWhatsApp, text: notes.whatsapp),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small button that copies [text] and says "Copied" for a moment.
class CopyButton extends StatefulWidget {
  const new({required this.label, required this.text, super.key});

  final String label;
  final String text;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    _reset?.cancel();
    setState(() {
      _reset = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _reset = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) => XpButton(
    label: _reset == null ? widget.label : context.l10n.copied,
    icon: PhosphorIconsRegular.copy,
    size: XpButtonSize.small,
    onPressed: _copy,
  );
}

/// The `min_version_*` reminder (D-22): when to raise the minimum version
/// in Firebase Remote Config if the release is a forced update. The engine
/// does not know whether it is one, so the copy says "if".
class MinVersionPanel extends StatelessWidget {
  const new({required this.release, super.key});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final stores = [for (final status in release.stores) status.store];
    final live = storesIn(release, StoreState.live);
    final later = [
      for (final store in stores)
        if (!live.contains(store)) store,
    ];
    final text = live.isEmpty
        ? l10n.minVersionLater(l10n.variableList(stores), release.version)
        : [
            l10n.minVersionNow(
              l10n.storeList(live),
              l10n.variableList(live),
              release.version,
            ),
            if (later.isNotEmpty)
              l10n.minVersionRest(
                l10n.variableList(later),
                l10n.storeList(later),
              ),
          ].join(' ');
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XpSectionLabel(l10n.minVersionTitle),
          const SizedBox(height: 8),
          Text(
            stores.isEmpty ? l10n.minVersionNoStores : text,
            style: context.xpType.body.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The reminder over a release that is live in every store
/// (`Release-A-BothLive.dc.html`).
class MinVersionBanner extends StatelessWidget {
  const new({required this.release, super.key});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final ink = colors.statusAttentionOnContainer;
    final stores = [for (final status in release.stores) status.store];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: colors.statusAttentionContainer,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: [
          XpSectionLabel(l10n.minVersionReminder, color: ink),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.minVersionBanner(l10n.variableList(stores), release.version),
              style: context.xpType.body.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The release pull request: its branches, what merging tags, and the run
/// that merges it.
class ReleasePrPanel extends StatelessWidget {
  const new({required this.release, super.key});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final caption = type.caption.copyWith(color: colors.textSecondary);
    final base = release.baseBranch ?? l10n.approvalBaseBranch;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              XpSectionLabel(l10n.prTitle),
              const Spacer(),
              if (release.prNumber case final number?)
                Text(
                  '#$number',
                  style: type.code.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (release.prNumber == null)
            Text(l10n.prNone, style: caption)
          else ...[
            Row(
              children: [
                if (release.branch case final branch?) ...[
                  XpCode(branch),
                  Text('  →  ', style: caption),
                ],
                XpCode(base),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              release.state == ReleaseState.merged
                  ? l10n.prMerged(shortSha(release.mergeCommit ?? ''))
                  : release.tag == null
                  ? l10n.prUntagged
                  : l10n.prTagged(release.tag!),
              style: caption,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (release.prUrl case final url?)
                  CopyButton(label: l10n.prCopyLink, text: url),
                if (release.mergeRunId case final runId?)
                  XpButton(
                    label: l10n.prOpenMergeJob,
                    icon: PhosphorIconsRegular.terminalWindow,
                    size: XpButtonSize.small,
                    kind: XpButtonKind.tertiary,
                    onPressed: () => context.read<ShellCubit>().show(
                      JobDestination(runId, projectId: release.projectId),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
