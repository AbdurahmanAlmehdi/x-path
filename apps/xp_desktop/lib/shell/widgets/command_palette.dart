import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/job/widgets/cancel_run_dialog.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/runners/bloc/runners_bloc.dart';
import 'package:xp_desktop/shell/bloc/command_palette_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/command_labels.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// ⌘K: opens the palette over [projectId], the project the shell shows,
/// and does the entry chosen.
Future<void> showCommandPalette(
  BuildContext context, {
  String? projectId,
}) async {
  final bloc = context.read<CommandPaletteBloc>()
    ..add(CommandPaletteOpened(projectId: projectId));
  final entry = await showDialog<PaletteEntry>(
    context: context,
    barrierColor: context.xpColors.scrimDefault,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: const CommandPalette()),
  );
  if (entry != null && context.mounted) {
    await performPaletteEntry(context, entry);
  }
}

/// Does [entry] from the shell's [context].
Future<void> performPaletteEntry(
  BuildContext context,
  PaletteEntry entry,
) async {
  final shell = context.read<ShellCubit>();
  final toasts = context.read<ToastCubit>();
  final jobs = context.read<JobsRepository>();
  if (entry.destination case final destination?) {
    shell.show(destination);
    return;
  }
  try {
    switch (entry) {
      case DispatchEntry(:final project):
        await dispatchFor(context, project);
      case RunAgainEntry(:final run):
        final again = await jobs.runAgain(run.id);
        shell.show(JobDestination(again.id, projectId: again.projectId));
      case CancelEntry(:final run, :final workflow):
        final runJobs = (await jobs.watchRunJobs(run.id).first).value;
        if (!context.mounted) return;
        final cancel = await confirmCancelRun(
          context,
          runJobs: runJobs,
          title: workflow ?? context.l10n.jobTitle,
          engineName:
              context.read<EngineConnectionBloc>().state.active?.name ?? '',
          runners: {
            for (final runner in context.read<RunnersBloc>().state.runners)
              runner.id: runner.name,
          },
        );
        if (cancel) await jobs.cancelRun(run.id);
      case ApproveEntry(:final approval):
        await showApprovalReview(context, approval.id);
      case GoToProject() ||
          GoToRelease() ||
          GoToRun() ||
          GoToWorkflow() ||
          GoToPage():
        break;
    }
  } on Exception catch (error) {
    toasts.show(errorMessage(error));
  }
}

/// What the palette shows for [entry].
String paletteLabel(AppLocalizations l10n, PaletteEntry entry) {
  String runName(Run run, String? workflow) =>
      [workflow ?? run.workflowId, run.version ?? shortSha(run.sha)].join(' ');
  return switch (entry) {
    GoToProject(:final project) => project.fullName,
    GoToRelease(:final release) => l10n.paletteRelease(
      '${release.version}+${release.build}',
      release.flavor,
    ),
    GoToRun(:final run, :final workflow) => l10n.paletteRun(
      runName(run, workflow),
    ),
    GoToWorkflow(:final workflow) => l10n.paletteWorkflow(
      workflow.title ?? workflow.name,
    ),
    GoToPage(:final page) => l10n.palettePage(pageLabel(l10n, page)),
    DispatchEntry(:final project) => l10n.paletteDispatch(project.fullName),
    RunAgainEntry(:final run, :final workflow) => l10n.paletteRunAgain(
      runName(run, workflow),
    ),
    CancelEntry(:final run, :final workflow) => l10n.paletteCancel(
      runName(run, workflow),
    ),
    ApproveEntry(:final approval) => l10n.paletteApprove(
      approval.action,
      approval.version ?? shortSha(approval.sha),
    ),
  };
}

/// The shortcut the palette shows at the end of [entry]'s row, if any.
String? paletteKeys(PaletteEntry entry) => switch (entry) {
  DispatchEntry() => XpCommand.dispatch.keys,
  CancelEntry() => XpCommand.cancel.keys,
  ApproveEntry() => XpCommand.approvals.keys,
  _ => null,
};

IconData _iconOf(PaletteEntry entry) => switch (entry) {
  GoToProject() => PhosphorIconsRegular.package,
  GoToRelease() => PhosphorIconsRegular.rocketLaunch,
  GoToRun() || RunAgainEntry() => PhosphorIconsRegular.playCircle,
  GoToWorkflow() => PhosphorIconsRegular.treeStructure,
  GoToPage() => PhosphorIconsRegular.arrowRight,
  DispatchEntry() => PhosphorIconsRegular.paperPlaneTilt,
  CancelEntry() => PhosphorIconsRegular.stop,
  ApproveEntry() => PhosphorIconsRegular.handPalm,
};

/// The palette: a field and the entries that match it. ↑ and ↓ move, ↩
/// chooses, Esc closes.
class CommandPalette extends StatefulWidget {
  const new({super.key});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  late final _field = FocusNode(onKeyEvent: _onKey);
  var _selected = 0;
  var _matches = const <PaletteEntry>[];

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  /// ↑, ↓ and ↩ act on the list before the field sees them.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        if (_matches.isNotEmpty) {
          Navigator.of(context).pop(_matches[_selected]);
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _field.requestFocus();
  }

  void _move(int by) {
    if (_matches.isEmpty) return;
    setState(() => _selected = (_selected + by) % _matches.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<CommandPaletteBloc>().state;
    final matches = _matches = state.matches(
      (entry) => paletteLabel(l10n, entry),
    );
    if (_selected >= matches.length) _selected = 0;
    final selected = _selected;
    void choose(PaletteEntry entry) => Navigator.of(context).pop(entry);
    return Dialog(
      alignment: const Alignment(0, -0.6),
      backgroundColor: colors.surfaceOverlay,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.xpRadii.lg),
        side: BorderSide(color: colors.borderStrong),
      ),
      child: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: XpTextField(
                key: const Key('palette.query'),
                controller: _query,
                focusNode: _field,
                hint: l10n.paletteHint,
                onChanged: (query) {
                  setState(() => _selected = 0);
                  context.read<CommandPaletteBloc>().add(
                    CommandPaletteQueryChanged(query),
                  );
                },
              ),
            ),
            const XpHairline(),
            Expanded(
              child: state.loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: XpLoading(),
                    )
                  : matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.paletteEmpty,
                        style: context.xpType.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: matches.length,
                      itemBuilder: (context, index) => _Row(
                        matches[index],
                        selected: index == selected,
                        onTap: () => choose(matches[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const new(this.entry, {required this.selected, required this.onTap});

  final PaletteEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final keys = paletteKeys(entry);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected ? colors.surfaceSelected : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Icon(
                _iconOf(entry),
                size: context.xpSizes.iconSm,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  paletteLabel(context.l10n, entry),
                  overflow: TextOverflow.ellipsis,
                  style: type.body.copyWith(color: colors.textPrimary),
                ),
              ),
              if (keys != null)
                Text(
                  keys,
                  style: type.code.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
