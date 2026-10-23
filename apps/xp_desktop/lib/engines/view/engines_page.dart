import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/engines/widgets/add_engine_form.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/engine_status_text.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The engines the app knows: the one on this Mac and remote ones added by
/// URL and token. One is shown at a time.
class EnginesPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<EngineConnectionBloc>().state;
    final hasLocal = state.engines.any((engine) => engine.isLocal);
    return ShellPage(
      title: l10n.enginesTitle,
      subtitle: l10n.enginesSubtitle,
      actions: [
        if (!hasLocal)
          XpButton(
            label: l10n.enginesSetUpLocal,
            icon: PhosphorIconsRegular.laptop,
            onPressed: () =>
                context.read<ShellCubit>().show(const OnboardingDestination()),
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          XpPanel(
            child: Column(
              children: [
                for (final (index, engine) in state.engines.indexed) ...[
                  if (index > 0) const XpHairline(),
                  _EngineRow(
                    engine: engine,
                    active: engine.id == state.active?.id,
                    status: state.status,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AddEngineForm(),
        ],
      ),
    );
  }
}

class _EngineRow extends StatelessWidget {
  const new({required this.engine, required this.active, required this.status});

  final EngineProfile engine;
  final bool active;
  final EngineStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final bloc = context.read<EngineConnectionBloc>();
    return Container(
      constraints: BoxConstraints(minHeight: context.xpSizes.rowDefault + 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            engine.isLocal
                ? PhosphorIconsRegular.laptop
                : PhosphorIconsRegular.hardDrives,
            size: context.xpSizes.iconMd,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Text(
            engine.name,
            style: context.xpType.titleSm.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: XpCode(engine.url.toString(), color: colors.textSecondary),
          ),
          const Spacer(),
          if (active) ...[
            XpStatusLabel(
              engineXpStatus(status),
              engineStatusLabel(l10n, status),
            ),
            const SizedBox(width: 12),
            XpBadge(XpStatus.engineConnected, l10n.enginesActive),
          ] else
            XpButton(
              label: l10n.enginesUse,
              size: XpButtonSize.small,
              onPressed: () => bloc.add(EngineSelected(engine.id)),
            ),
          const SizedBox(width: 8),
          XpButton(
            label: l10n.enginesRemove,
            kind: XpButtonKind.tertiary,
            size: XpButtonSize.small,
            onPressed: () => removeEngine(context, engine),
          ),
        ],
      ),
    );
  }
}

/// Asks, then removes [engine] from this Mac (UX-08).
Future<void> removeEngine(BuildContext context, EngineProfile engine) async {
  final l10n = context.l10n;
  final bloc = context.read<EngineConnectionBloc>();
  final confirmed = await confirmAction(
    context,
    title: l10n.enginesRemoveTitle(engine.name),
    points: [l10n.enginesRemoveForget(engine.name), l10n.enginesRemoveKeeps],
    keep: l10n.confirmKeep,
    confirm: l10n.enginesRemove,
  );
  if (confirmed) bloc.add(EngineRemoved(engine.id));
}
