import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/runners/bloc/runners_bloc.dart';
import 'package:xp_desktop/runners/widgets/revoke_runner_dialog.dart';
import 'package:xp_desktop/runners/widgets/runner_labels.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The runners that may run jobs: status, capabilities from the engine's
/// probe (D-19), slots, the jobs they hold a lease for and when the engine
/// last heard from them, with "Revoke…".
class RunnersTable extends StatelessWidget {
  const new({required this.runners, super.key});

  final List<Runner> runners;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final columns = [
      l10n.runnersColumnRunner,
      l10n.runnersColumnStatus,
      l10n.runnersColumnCapabilities,
      l10n.runnersColumnSlots,
      l10n.runnersColumnJobs,
      l10n.runnersColumnLastHeard,
      '',
    ];
    return XpPanel(
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(1.8),
          1: FlexColumnWidth(1.3),
          2: FlexColumnWidth(1.6),
          3: FixedColumnWidth(72),
          4: FlexColumnWidth(1.4),
          5: FlexColumnWidth(),
          6: FixedColumnWidth(136),
        },
        children: [
          TableRow(
            children: [
              for (final column in columns) _Cell(XpSectionLabel(column)),
            ],
          ),
          for (final runner in runners)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              children: _row(context, runner),
            ),
        ],
      ),
    );
  }

  List<Widget> _row(BuildContext context, Runner runner) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final state = context.watch<RunnersBloc>().state;
    final now = XpClock.now(context);
    final secondary = type.caption.copyWith(color: colors.textSecondary);
    final code = type.code.copyWith(color: colors.textPrimary);
    final machine = runnerMachine(runner, l10n);
    final heard = runner.lastHeartbeat;
    return [
      _Cell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              runner.name,
              overflow: TextOverflow.ellipsis,
              style: type.titleSm.copyWith(color: colors.textPrimary),
            ),
            if (machine.isNotEmpty)
              Text(
                machine,
                overflow: TextOverflow.ellipsis,
                style: type.code.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
      ),
      _Cell(
        XpStatusLabel(
          runnerStatus(runner),
          runnerStatusLabel(runner, l10n),
          style: type.body,
        ),
      ),
      _Cell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            if (runner.capabilities.isEmpty && runner.missing == null)
              Text(l10n.runnerNotProbed, style: secondary)
            else if (runner.capabilities.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final capability in runner.capabilities)
                    _Capability(capability),
                ],
              ),
            // Inline, not in a tooltip: the reason is what the owner acts on.
            for (final missing in runner.missing ?? const <MissingCapability>[])
              Text(
                l10n.runnerMissingCapability(
                  missing.capability,
                  missing.explanation,
                ),
                style: secondary,
              ),
          ],
        ),
      ),
      _Cell(Text('${runner.jobIds.length}/${runner.slots}', style: code)),
      _Cell(
        runner.jobIds.isEmpty
            ? Text('—', style: secondary)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final job in runner.jobIds)
                    Text(job, overflow: TextOverflow.ellipsis, style: code),
                ],
              ),
      ),
      _Cell(
        heard == null
            ? Text(l10n.runnerNeverHeard, style: secondary)
            : Tooltip(
                message: formatDateTime(heard),
                child: Text(
                  formatRelative(
                    heard,
                    now,
                    justNow: l10n.timeJustNow,
                    ago: l10n.timeAgo,
                    yesterday: l10n.timeYesterday,
                  ),
                  style: secondary,
                ),
              ),
      ),
      _Cell(
        XpButton(
          label: l10n.runnerRevoke,
          size: XpButtonSize.small,
          kind: XpButtonKind.tertiary,
          busy: state.revoking == runner.id,
          tooltip: context.canCommand ? null : l10n.readOnlyHint,
          onPressed: context.canCommand && state.revoking == null
              ? () => revokeRunner(context, runner)
              : null,
        ),
      ),
    ];
  }
}

/// Asks, then revokes [runner].
Future<void> revokeRunner(BuildContext context, Runner runner) async {
  final bloc = context.read<RunnersBloc>();
  if (await confirmRevokeRunner(context, runner)) {
    bloc.add(RunnerRevokeRequested(runner.id));
  }
}

/// The revoked runners: their names stay taken (D-08).
class RevokedRunners extends StatelessWidget {
  const new({required this.runners, super.key});

  final List<Runner> runners;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpSectionLabel(l10n.runnersRevokedTitle),
        const SizedBox(height: 8),
        for (final runner in runners)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsRegular.prohibit,
                  size: context.xpSizes.iconSm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  runner.name,
                  style: type.body.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(width: 8),
                Text(
                  runner.revokedAt == null
                      ? l10n.runnerRevoked
                      : l10n.runnerRevokedAt(formatDateTime(runner.revokedAt!)),
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Capability extends StatelessWidget {
  const new(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(context.xpRadii.sm),
      border: Border.all(color: context.xpColors.borderDefault),
    ),
    child: Text(
      name,
      style: context.xpType.code.copyWith(color: context.xpColors.textPrimary),
    ),
  );
}

class _Cell extends StatelessWidget {
  const new(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 12, 8), child: child);
}
