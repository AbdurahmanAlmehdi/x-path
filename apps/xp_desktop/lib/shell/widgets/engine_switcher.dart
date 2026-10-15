import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/engine_status_text.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The engine button at the top of the sidebar: the status of the active
/// engine, its name and a menu to switch engines or manage them.
class EngineSwitcher extends StatelessWidget {
  const new({super.key});

  /// The menu entry that opens the engine list.
  static const manage = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EngineConnectionBloc>().state;
    final colors = context.xpColors;
    final type = context.xpType;
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: (engineId) => engineId == manage
          ? context.read<ShellCubit>().show(const EnginesDestination())
          : context.read<EngineConnectionBloc>().add(EngineSelected(engineId)),
      itemBuilder: (context) => [
        for (final engine in state.engines)
          PopupMenuItem(
            value: engine.id,
            height: context.xpSizes.rowDefault,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: engine.id == state.active?.id
                      ? Icon(
                          PhosphorIconsRegular.check,
                          size: context.xpSizes.iconSm,
                          color: colors.textPrimary,
                        )
                      : null,
                ),
                Flexible(
                  child: Text(
                    engine.name,
                    overflow: TextOverflow.ellipsis,
                    style: type.body,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    engine.url.authority,
                    overflow: TextOverflow.ellipsis,
                    style: type.code.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: manage,
          height: context.xpSizes.rowDefault,
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(l10n.engineMenuManage, style: type.body),
          ),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(context.xpRadii.md),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Row(
          children: [
            XpStatusIcon(engineXpStatus(state.status)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.active?.name ?? '',
                overflow: TextOverflow.ellipsis,
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
            ),
            Text(
              engineStatusLabel(l10n, state.status).toLowerCase(),
              style: type.code.copyWith(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              PhosphorIconsRegular.caretDown,
              size: context.xpSizes.iconXs,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
