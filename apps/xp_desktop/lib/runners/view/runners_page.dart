import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/runners/bloc/runners_bloc.dart';
import 'package:xp_desktop/runners/view/pair_runner_sheet.dart';
import 'package:xp_desktop/runners/widgets/runners_table.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The runners of the engine (PRODUCT §6.8): machines, capabilities, slots,
/// current jobs, and pairing a new one.
class RunnersPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<RunnersBloc>().state;
    final active = state.active;
    final revoked = state.revoked;
    final canCommand = context.canCommand;
    return ShellPage(
      title: l10n.runnersTitle,
      cached: state.cached,
      subtitle: active.isEmpty
          ? null
          : l10n.runnersSubtitle(active.length, state.busy),
      actions: [
        XpButton(
          label: l10n.runnersPair,
          icon: PhosphorIconsRegular.plus,
          kind: XpButtonKind.primary,
          tooltip: canCommand ? null : l10n.readOnlyHint,
          onPressed: canCommand
              ? () => unawaited(showPairRunnerSheet(context))
              : null,
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.error case final error? when state.runners.isEmpty)
            XpErrorState(
              error,
              onRetry: () => context.read<RunnersBloc>().add(
                const RunnersSubscriptionRequested(),
              ),
            )
          else if (state.error case final error?) ...[
            XpMessage.error(error),
            const SizedBox(height: 12),
          ],
          if (!state.loaded)
            const XpLoading(rows: 3)
          else if (active.isNotEmpty)
            RunnersTable(runners: active)
          else if (state.error == null)
            const _NoRunners(),
          if (revoked.isNotEmpty) ...[
            const SizedBox(height: 24),
            RevokedRunners(runners: revoked),
          ],
        ],
      ),
    );
  }
}

class _NoRunners extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            PhosphorIconsRegular.hardDrives,
            size: context.xpSizes.iconXl,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.runnersEmptyTitle,
            style: context.xpType.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              l10n.runnersEmptyBody,
              textAlign: TextAlign.center,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
