import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/releases/bloc/release_board_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Where a Shorebird patch of a release is, from its history.
enum PatchState { published, promoted, rolledBack }

/// The Shorebird patches of a release, oldest first, each where its last
/// change in [history] left it.
List<(int, PatchState)> releasePatches(List<ReleaseEvent> history) {
  final patches = <int, PatchState>{};
  for (final event in history) {
    final number = event.patchNumber;
    if (number == null) continue;
    final state = switch (event.kind) {
      ReleaseEventKind.patch => patches[number] ?? PatchState.published,
      ReleaseEventKind.patchPromoted => PatchState.promoted,
      ReleaseEventKind.patchRolledBack => PatchState.rolledBack,
      _ => null,
    };
    if (state != null) patches[number] = state;
  }
  return [
    for (final number in patches.keys.toList()..sort())
      (number, patches[number]!),
  ];
}

/// The Shorebird patches of the shown release, with Promote and Roll back
/// (U7b). Each change waits for the owner's approval at `prod_patch`.
class ReleasePatchesPanel extends StatelessWidget {
  const new({required this.patches, super.key});

  final List<(int, PatchState)> patches;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final bloc = context.read<ReleaseBoardBloc>();
    final board = context.watch<ReleaseBoardBloc>().state;
    final canCommand = context.canCommand;
    final enabled = canCommand && board.command == ReleaseCommand.none;
    final tooltip = canCommand ? null : l10n.readOnlyHint;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XpSectionLabel(l10n.patchesTitle),
          const SizedBox(height: 10),
          for (final (number, state) in patches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.patchLabel(number)} · ${switch (state) {
                        PatchState.published => l10n.patchPublished,
                        PatchState.promoted => l10n.patchPromoted,
                        PatchState.rolledBack => l10n.patchRolledBack,
                      }}',
                      style: type.body.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  if (state != PatchState.promoted)
                    XpButton(
                      label: l10n.patchPromote,
                      size: XpButtonSize.small,
                      tooltip: tooltip,
                      onPressed: enabled
                          ? () => bloc.add(
                              ReleaseBoardPatchMoved(
                                number,
                                PatchAction.promote,
                              ),
                            )
                          : null,
                    ),
                  if (state != PatchState.rolledBack) ...[
                    const SizedBox(width: 8),
                    XpButton(
                      label: l10n.patchRollback,
                      size: XpButtonSize.small,
                      tooltip: tooltip,
                      onPressed: enabled
                          ? () => bloc.add(
                              ReleaseBoardPatchMoved(
                                number,
                                PatchAction.rollback,
                              ),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          Text(
            l10n.patchesCaption,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
