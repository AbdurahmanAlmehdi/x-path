import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Asks for the name of a new workflow, offering [initial]; `null` when the
/// owner cancels. Save waits until the name is one the engine takes and not
/// one of [taken]. [title] says what the name is for, saving as a new
/// workflow by default.
Future<String?> askWorkflowName(
  BuildContext context, {
  String? initial,
  Set<String> taken = const {},
  String? title,
}) => showDialog<String>(
  context: context,
  barrierColor: context.xpColors.scrimDefault,
  builder: (_) =>
      WorkflowNameDialog(initial: initial ?? '', taken: taken, title: title),
);

/// What the engine takes as a workflow name (`workflow_service.dart`).
final workflowNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

/// The name a copy of [name] is offered: `<name>-copy`, then `<name>-copy-2`
/// and on, the first that is not [taken].
String copyName(String name, Set<String> taken) {
  final base = '$name-copy';
  var candidate = base;
  for (var n = 2; taken.contains(candidate); n++) {
    candidate = '$base-$n';
  }
  return candidate;
}

/// Asks before dropping the unsaved changes to [name]; `true` to drop them.
/// Return does nothing, Escape keeps them.
Future<bool> confirmDiscard(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => DiscardChangesDialog(name: name),
    ) ??
    false;

/// Asks which of [steps] to add: grouped as the engine groups them,
/// searchable by kind, title and description; `null` when the owner
/// closes it.
Future<String?> pickStepType(BuildContext context, List<StepType> steps) =>
    showDialog<String>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => StepPickerDialog(steps: steps),
    );

/// Asks which of [templates] a new workflow starts from; `null` when the
/// owner closes it.
Future<WorkflowTemplate?> pickTemplate(
  BuildContext context,
  List<WorkflowTemplate> templates,
) => showDialog<WorkflowTemplate>(
  context: context,
  barrierColor: context.xpColors.scrimDefault,
  builder: (context) {
    final colors = context.xpColors;
    final type = context.xpType;
    return _BuilderDialog(
      title: context.l10n.workflowsTemplateTitle,
      children: [
        for (final template in templates)
          InkWell(
            key: ValueKey(('template', template.id)),
            onTap: () => Navigator.of(context).pop(template),
            borderRadius: BorderRadius.circular(context.xpRadii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.title,
                    style: type.body.copyWith(color: colors.textPrimary),
                  ),
                  Text(
                    template.description,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            XpButton(
              label: context.l10n.workflowsCancel,
              size: XpButtonSize.large,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  },
);

/// The groups of the engine's step types, in the order of a pipeline.
const _stepGroups = ['Source', 'Checks', 'Build', 'Upload', 'GitHub', 'Other'];

class StepPickerDialog extends StatefulWidget {
  const new({required this.steps, super.key});

  final List<StepType> steps;

  @override
  State<StepPickerDialog> createState() => _StepPickerDialogState();
}

class _StepPickerDialogState extends State<StepPickerDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The step types that match the search, by group.
  Map<String, List<StepType>> get _groups {
    final query = _search.text.trim().toLowerCase();
    final groups = <String, List<StepType>>{
      for (final group in _stepGroups) group: [],
    };
    for (final step in widget.steps) {
      final text = '${step.kind} ${step.title} ${step.description}';
      if (!text.toLowerCase().contains(query)) continue;
      (groups[step.group.isEmpty ? 'Other' : step.group] ??= []).add(step);
    }
    return {
      for (final MapEntry(:key, :value) in groups.entries)
        if (value.isNotEmpty) key: value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final groups = _groups;
    return _BuilderDialog(
      title: l10n.workflowsStepPickerTitle,
      children: [
        XpTextField(
          controller: _search,
          hint: l10n.workflowsStepSearchHint,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: groups.isEmpty
              ? Text(
                  l10n.workflowsStepNoMatch,
                  style: type.body.copyWith(color: colors.textSecondary),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final MapEntry(key: group, value: steps)
                        in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: XpSectionLabel(group),
                      ),
                      for (final step in steps)
                        InkWell(
                          key: ValueKey(('step-type', step.kind)),
                          onTap: () => Navigator.of(context).pop(step.kind),
                          borderRadius: BorderRadius.circular(
                            context.xpRadii.md,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      step.title.isEmpty
                                          ? step.kind
                                          : step.title,
                                      style: type.body.copyWith(
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    XpCode(
                                      step.kind,
                                      color: colors.textSecondary,
                                    ),
                                  ],
                                ),
                                if (step.description.isNotEmpty)
                                  Text(
                                    step.description,
                                    style: type.caption.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            XpButton(
              label: l10n.workflowsCancel,
              size: XpButtonSize.large,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _BuilderDialog extends StatelessWidget {
  const new({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
            ],
          ),
        ),
      ),
    );
  }
}

class WorkflowNameDialog extends StatefulWidget {
  const new({
    required this.initial,
    this.taken = const {},
    this.title,
    super.key,
  });

  final String initial;

  /// What the name is for; saving as a new workflow by default.
  final String? title;

  /// The names of the project's workflows, built-ins included.
  final Set<String> taken;

  @override
  State<WorkflowNameDialog> createState() => _WorkflowNameDialogState();
}

class _WorkflowNameDialogState extends State<WorkflowNameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Why the name cannot be saved, or `null` when it can.
  String? _problem(String name) {
    final l10n = context.l10n;
    if (name.isEmpty) return null;
    if (!workflowNamePattern.hasMatch(name)) return l10n.workflowsNameInvalid;
    if (widget.taken.contains(name)) return l10n.workflowsNameTaken(name);
    return null;
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty && _problem(name) == null) {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = _name.text.trim();
    final problem = _problem(name);
    return _BuilderDialog(
      title: widget.title ?? l10n.workflowsNameTitle,
      children: [
        XpTextField(
          label: l10n.workflowsName,
          controller: _name,
          code: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          problem ?? l10n.workflowsNameBody,
          style: context.xpType.caption.copyWith(
            color: problem == null
                ? context.xpColors.textSecondary
                : context.xpColors.negativeDefault,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            XpButton(
              label: l10n.workflowsCancel,
              size: XpButtonSize.large,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            XpButton(
              label: l10n.workflowsSave,
              kind: XpButtonKind.primary,
              size: XpButtonSize.large,
              onPressed: name.isEmpty || problem != null ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
}

class DiscardChangesDialog extends StatelessWidget {
  const new({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void close({required bool discard}) => Navigator.of(context).pop(discard);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            close(discard: false),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter):
              DoNothingAndStopPropagationIntent(),
        },
        child: Focus(
          autofocus: true,
          child: _BuilderDialog(
            title: l10n.workflowsDiscardTitle,
            children: [
              Text(
                l10n.workflowsDiscardBody(name),
                style: context.xpType.body.copyWith(
                  color: context.xpColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  XpButton(
                    label: l10n.workflowsKeepEditing,
                    size: XpButtonSize.large,
                    onPressed: () => close(discard: false),
                  ),
                  const SizedBox(width: 8),
                  XpButton(
                    label: l10n.workflowsDiscard,
                    kind: XpButtonKind.destructive,
                    size: XpButtonSize.large,
                    onPressed: () => close(discard: true),
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
