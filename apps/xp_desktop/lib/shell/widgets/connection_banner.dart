import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/engine_status_text.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The bar under the toolbar while the engine is not plainly connected:
/// reconnecting, unreachable (the screens show the cached snapshot,
/// read-only), secrets locked, or a refused token. Built like the needs-you
/// bar of `Main.dc.html`, in the status's own pair; nothing shows while
/// connected or during the first check.
class ConnectionBanner extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EngineConnectionBloc>().state;
    final engine = state.active?.name ?? '';
    final l10n = context.l10n;
    final message = switch (state.status) {
      EngineStatus.connected || EngineStatus.connecting => null,
      EngineStatus.reconnecting => l10n.bannerReconnecting(engine),
      EngineStatus.unreachable => l10n.bannerUnreachable(engine),
      EngineStatus.secretsLocked => l10n.bannerSecretsLocked(engine),
      EngineStatus.rejected => l10n.bannerRejected(engine),
    };
    if (message == null) return const SizedBox.shrink();
    final status = engineXpStatus(state.status);
    final colors = context.xpColors;
    final ink = colors.onContainer(status.pair);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: colors.container(status.pair),
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            XpStatusIcon(status, size: context.xpSizes.iconMd),
            const SizedBox(width: 8),
            XpSectionLabel(engineStatusLabel(l10n, state.status), color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: context.xpType.body.copyWith(color: ink),
              ),
            ),
            const SizedBox(width: 12),
            if (state.status != EngineStatus.rejected)
              XpButton(
                label: l10n.bannerRetry,
                size: XpButtonSize.small,
                onPressed: () => context.read<EngineConnectionBloc>().add(
                  const EngineCheckRequested(),
                ),
              ),
            const SizedBox(width: 8),
            XpButton(
              label: l10n.bannerEngines,
              kind: XpButtonKind.tertiary,
              size: XpButtonSize.small,
              onPressed: () =>
                  context.read<ShellCubit>().show(const EnginesDestination()),
            ),
          ],
        ),
      ),
    );
  }
}
