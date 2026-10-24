import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_builder_bloc.dart';

/// [before] against [after], a line each: added lines on the positive tint,
/// removed ones on the negative, in code type.
class XpDiffView extends StatelessWidget {
  const new({required this.before, required this.after, super.key});

  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final lines = diffLines(before, after);
    if (lines.every((line) => line.kind == DiffKind.same)) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          context.l10n.workflowsNoChanges,
          style: type.body.copyWith(color: colors.textSecondary),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final line in lines)
            ColoredBox(
              color: switch (line.kind) {
                DiffKind.same => Colors.transparent,
                DiffKind.added => colors.statusPositiveContainer,
                DiffKind.removed => colors.statusNegativeContainer,
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '$line',
                  style: type.code.copyWith(
                    color: switch (line.kind) {
                      DiffKind.same => colors.textSecondary,
                      DiffKind.added => colors.statusPositiveOnContainer,
                      DiffKind.removed => colors.statusNegativeOnContainer,
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The versions of the open workflow: any two compared, and an older one
/// saved again as the newest.
Future<void> showWorkflowVersions(BuildContext context) {
  final bloc = context.read<WorkflowBuilderBloc>();
  final versions = bloc.state.workflow!.versions;
  bloc.add(
    WorkflowVersionsCompared(
      versions.length > 1
          ? versions[versions.length - 2].version
          : versions.last.version,
      versions.last.version,
    ),
  );
  return showDialog<void>(
    context: context,
    barrierColor: context.xpColors.scrimDefault,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: const WorkflowVersionsDialog()),
  );
}

class WorkflowVersionsDialog extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bloc = context.read<WorkflowBuilderBloc>();
    final state = context.watch<WorkflowBuilderBloc>().state;
    final workflow = state.workflow;
    if (workflow == null) return const SizedBox();
    final diff = state.versionDiff;
    final numbers = [for (final v in workflow.versions) v.version];
    String label(int number) {
      final saved = workflow.versions.firstWhere((v) => v.version == number);
      return l10n.workflowsVersionLabel(
        number,
        formatAbsolute(saved.createdAt),
      );
    }

    final newest = workflow.versions.last.version;
    return _HistoryDialog(
      title: l10n.workflowsVersionsTitle(workflow.name),
      actions: [
        if (!workflow.builtin && diff != null && diff.from != newest)
          XpButton(
            label: l10n.workflowsRestoreVersion(diff.from),
            size: XpButtonSize.large,
            onPressed: context.canCommand
                ? () {
                    bloc.add(WorkflowVersionRestored(diff.from));
                    Navigator.of(context).pop();
                  }
                : null,
          ),
      ],
      children: [
        Row(
          children: [
            Text(l10n.workflowsVersionFrom),
            const SizedBox(width: 8),
            XpSelect<int>(
              value: diff?.from ?? numbers.first,
              values: numbers,
              labelOf: label,
              onChanged: (from) =>
                  bloc.add(WorkflowVersionsCompared(from, diff?.to ?? newest)),
            ),
            const SizedBox(width: 16),
            Text(l10n.workflowsVersionTo),
            const SizedBox(width: 8),
            XpSelect<int>(
              value: diff?.to ?? newest,
              values: numbers,
              labelOf: label,
              onChanged: (to) => bloc.add(
                WorkflowVersionsCompared(diff?.from ?? numbers.first, to),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: diff == null
              ? const _Loading()
              : XpDiffView(
                  key: ValueKey((diff.from, diff.to)),
                  before: diff.before,
                  after: diff.after,
                ),
        ),
      ],
    );
  }
}

/// The copy of a built-in against the built-in: what the built-in changed
/// since the copy was made, and what the copy changed.
Future<void> showBuiltinCompare(BuildContext context) {
  final bloc = context.read<WorkflowBuilderBloc>()
    ..add(const WorkflowBuiltinCompared());
  return showDialog<void>(
    context: context,
    barrierColor: context.xpColors.scrimDefault,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: const BuiltinCompareDialog()),
  );
}

class BuiltinCompareDialog extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bloc = context.read<WorkflowBuilderBloc>();
    final state = context.watch<WorkflowBuilderBloc>().state;
    final compare = state.builtinCompare;
    Widget pane(String title, Widget child) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XpSectionLabel(title),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
    return _HistoryDialog(
      title: l10n.workflowsCompareTitle(
        compare?.builtin ?? state.workflow?.basedOn?.builtin ?? '',
      ),
      actions: [
        XpButton(
          label: l10n.workflowsMarkUpToDate,
          kind: XpButtonKind.primary,
          size: XpButtonSize.large,
          onPressed: compare != null && context.canCommand
              ? () {
                  bloc.add(const WorkflowCaughtUp());
                  Navigator.of(context).pop();
                }
              : null,
        ),
      ],
      children: [
        Expanded(
          child: compare == null
              ? const _Loading()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pane(
                      l10n.workflowsBuiltinChanged(
                        compare.builtin,
                        compare.base,
                        compare.latest,
                      ),
                      XpDiffView(
                        before: compare.baseYaml,
                        after: compare.latestYaml,
                      ),
                    ),
                    const SizedBox(width: 12),
                    pane(
                      l10n.workflowsYouChanged(compare.base),
                      XpDiffView(before: compare.baseYaml, after: state.yaml),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Dialog(
      backgroundColor: colors.surfaceOverlay,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.xpRadii.lg),
        side: BorderSide(color: colors.borderStrong),
      ),
      child: SizedBox(
        width: 960,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: context.xpType.headline.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in actions) ...[
                    action,
                    const SizedBox(width: 8),
                  ],
                  XpButton(
                    label: context.l10n.workflowsClose,
                    size: XpButtonSize.large,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Center(
    child: XpSpinner(
      icon: PhosphorIconsRegular.circleNotch,
      size: context.xpSizes.iconMd,
      color: context.xpColors.textSecondary,
    ),
  );
}
