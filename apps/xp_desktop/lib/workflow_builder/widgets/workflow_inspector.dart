import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_edits.dart';
import 'package:xp_desktop/workflow_builder/widgets/builder_controls.dart';
import 'package:xp_desktop/workflow_builder/widgets/workflow_dialogs.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Called with the edited document and, when it changes, what to select.
typedef DocumentEdit = void Function(
  WorkflowDocument document, [
  WorkflowSelection? selection,
]);

/// The matrix axes and platforms when the engine's schema is not known.
const _fallbackAxes = ['platform', 'flavor'];
const _fallbackPlatforms = ['android', 'ios'];

/// The fields of what the pipeline has selected: the workflow (name,
/// description, lock, inputs), a stage (its name and place), or a job (id,
/// name, `if`, matrix, capabilities and its steps with `if`, gate and
/// `with`).
class WorkflowInspector extends StatelessWidget {
  const new({
    required this.document,
    required this.selection,
    required this.onEdit,
    required this.onRemoved,
    this.schema,
    this.enabled = true,
    super.key,
  });

  final WorkflowDocument document;
  final WorkflowSelection selection;
  final DocumentEdit onEdit;

  /// Called with what a removal takes out, just before the removal, to
  /// offer its undo.
  final ValueChanged<String> onRemoved;

  /// The step types, gates and capabilities to offer; free text without.
  final WorkflowSchema? schema;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final stage = selection.stage;
    final job = selection.job;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: switch ((stage, job)) {
        (final int stage, final int job) => _JobFields(
          key: ValueKey(('job', stage, job)),
          document: document,
          stage: stage,
          job: job,
          schema: schema,
          enabled: enabled,
          onEdit: onEdit,
          onRemoved: onRemoved,
        ),
        (final int stage, null) => _StageFields(
          key: ValueKey(('stage', stage)),
          document: document,
          stage: stage,
          enabled: enabled,
          onEdit: onEdit,
          onRemoved: onRemoved,
        ),
        _ => _WorkflowFields(
          document: document,
          enabled: enabled,
          onEdit: onEdit,
          onRemoved: onRemoved,
        ),
      },
    );
  }
}

class _WorkflowFields extends StatelessWidget {
  const new({
    required this.document,
    required this.enabled,
    required this.onEdit,
    required this.onRemoved,
  });

  final WorkflowDocument document;
  final bool enabled;
  final DocumentEdit onEdit;
  final ValueChanged<String> onRemoved;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    String? orNull(String text) => text.isEmpty ? null : text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoundTextField(
          label: l10n.workflowsName,
          value: document.name ?? '',
          enabled: enabled,
          onChanged: (text) =>
              onEdit(document.copyWith(name: () => orNull(text))),
        ),
        const SizedBox(height: 12),
        BoundTextField(
          label: l10n.workflowsDescription,
          value: document.description ?? '',
          maxLines: 3,
          enabled: enabled,
          onChanged: (text) =>
              onEdit(document.copyWith(description: () => orNull(text))),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: XpChip(
            label: l10n.workflowsLock,
            icon: PhosphorIconsRegular.lockSimple,
            selected: document.locksProject,
            onChanged: enabled
                ? (value) => onEdit(document.copyWith(locksProject: value))
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.workflowsLockHint,
          style: context.xpType.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            XpSectionLabel(l10n.workflowsInputs),
            const Spacer(),
            XpButton(
              label: l10n.workflowsAddInput,
              icon: PhosphorIconsRegular.plus,
              kind: XpButtonKind.tertiary,
              size: XpButtonSize.small,
              onPressed: enabled ? () => onEdit(document.addInput()) : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (document.inputs.isEmpty)
          Text(
            l10n.workflowsNoInputs,
            style: context.xpType.body.copyWith(color: colors.textSecondary),
          ),
        for (final (index, input) in document.inputs.indexed)
          InputEditor(
            key: ValueKey(('input', index)),
            input: input,
            enabled: enabled,
            onChanged: (value) =>
                onEdit(document.editInput(index, (_) => value)),
            onRemove: () {
              onRemoved(l10n.workflowsRemovedInput(input.name));
              onEdit(document.removeInput(index));
            },
          ),
        const SizedBox(height: 4),
        Text(
          l10n.workflowsInputsHint,
          style: context.xpType.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _StageFields extends StatelessWidget {
  const new({
    required this.document,
    required this.stage,
    required this.enabled,
    required this.onEdit,
    required this.onRemoved,
    super.key,
  });

  final WorkflowDocument document;
  final int stage;
  final bool enabled;
  final DocumentEdit onEdit;
  final ValueChanged<String> onRemoved;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            XpSectionLabel(l10n.workflowsStage(stage + 1)),
            const Spacer(),
            OrderActions(
              index: stage,
              count: document.stages.length,
              enabled: enabled,
              earlier: l10n.workflowsMoveEarlier,
              later: l10n.workflowsMoveLater,
              remove: l10n.workflowsRemoveStage,
              onMove: (delta) => onEdit(
                document.moveStage(stage, delta),
                WorkflowSelection(stage: stage + delta),
              ),
              onRemove: () {
                onRemoved(
                  l10n.workflowsRemovedStage(document.stages[stage].name),
                );
                onEdit(document.removeStage(stage), WorkflowSelection.workflow);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        BoundTextField(
          label: l10n.workflowsStageName,
          value: document.stages[stage].name,
          enabled: enabled,
          onChanged: (text) =>
              onEdit(document.editStage(stage, (s) => s.copyWith(name: text))),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.workflowsSelectJob,
          style: context.xpType.caption.copyWith(
            color: context.xpColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _JobFields extends StatelessWidget {
  const new({
    required this.document,
    required this.stage,
    required this.job,
    required this.schema,
    required this.enabled,
    required this.onEdit,
    required this.onRemoved,
    super.key,
  });

  final WorkflowDocument document;
  final int stage;
  final int job;
  final WorkflowSchema? schema;
  final bool enabled;
  final DocumentEdit onEdit;
  final ValueChanged<String> onRemoved;

  WorkflowJob get _job => document.stages[stage].jobs[job];

  void _edit(WorkflowJob Function(WorkflowJob job) edit) =>
      onEdit(document.editJob(stage, job, edit));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _job;
    String? orNull(String text) => text.trim().isEmpty ? null : text;
    final capabilities = {...?schema?.capabilities, ...current.capabilities};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            XpSectionLabel(
              '${l10n.workflowsStage(stage + 1)} · ${l10n.workflowsJob}',
            ),
            const Spacer(),
            OrderActions(
              index: job,
              count: document.stages[stage].jobs.length,
              enabled: enabled,
              earlier: l10n.workflowsMoveEarlier,
              later: l10n.workflowsMoveLater,
              remove: l10n.workflowsRemoveJob,
              onMove: (delta) => onEdit(
                document.moveJob(stage, job, delta),
                WorkflowSelection(stage: stage, job: job + delta),
              ),
              onRemove: () {
                onRemoved(l10n.workflowsRemovedJob(current.id));
                onEdit(
                  document.removeJob(stage, job),
                  WorkflowSelection(stage: stage),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BoundTextField(
                label: l10n.workflowsJobId,
                value: current.id,
                code: true,
                enabled: enabled,
                onChanged: (text) => _edit((j) => j.copyWith(id: text.trim())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: BoundTextField(
                label: l10n.workflowsJobName,
                value: current.name ?? '',
                hint: l10n.workflowsJobNameHint,
                enabled: enabled,
                onChanged: (text) =>
                    _edit((j) => j.copyWith(name: () => orNull(text))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        BoundTextField(
          label: l10n.workflowsCondition,
          value: current.condition ?? '',
          hint: l10n.workflowsConditionHint,
          code: true,
          enabled: enabled,
          onChanged: (text) =>
              _edit((j) => j.copyWith(condition: () => orNull(text))),
        ),
        const SizedBox(height: 16),
        XpSectionLabel(l10n.workflowsMatrix),
        const SizedBox(height: 6),
        for (final axis in {
          ...schema?.matrixAxes ?? _fallbackAxes,
          ...current.matrix.map((a) => a.name),
        })
          _AxisRow(
            name: axis,
            axis: current.axis(axis),
            platforms: schema?.platforms ?? _fallbackPlatforms,
            enabled: enabled,
            onChanged: (value) => _edit((j) => j.withAxis(axis, value)),
          ),
        const SizedBox(height: 10),
        XpSectionLabel(l10n.workflowsCapabilities),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final capability in capabilities)
              XpChip(
                label: capability,
                selected: current.capabilities.contains(capability),
                onChanged: enabled
                    ? (on) => _edit(
                        (j) => j.copyWith(
                          capabilities: on
                              ? [...j.capabilities, capability]
                              : [
                                  for (final c in j.capabilities)
                                    if (c != capability) c,
                                ],
                        ),
                      )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            XpSectionLabel(l10n.workflowsStepsLabel),
            const Spacer(),
            _AddStep(
              steps: schema?.steps,
              enabled: enabled,
              onAdd: (kind) => _edit((j) => j.addStep(kind)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final (index, step) in current.steps.indexed)
          StepEditor(
            key: ValueKey(('step', stage, job, index)),
            index: index,
            count: current.steps.length,
            step: step,
            schema: schema,
            variables: [
              ...?schema?.variables,
              for (final input in document.inputs) 'inputs.${input.name}',
            ],
            enabled: enabled,
            onChanged: (value) => _edit((j) => j.editStep(index, (_) => value)),
            onMove: (delta) => _edit((j) => j.moveStep(index, delta)),
            onRemove: () {
              onRemoved(l10n.workflowsRemovedStep(step.kind));
              _edit((j) => j.removeStep(index));
            },
          ),
      ],
    );
  }
}

enum _AxisMode { none, dispatch, list }

/// One axis of the matrix: off, from the dispatch (`${{ platforms }}`), or
/// listed: chips for platforms, text for flavors.
class _AxisRow extends StatelessWidget {
  const new({
    required this.name,
    required this.axis,
    required this.platforms,
    required this.enabled,
    required this.onChanged,
  });

  final String name;
  final WorkflowMatrixAxis? axis;
  final List<String> platforms;
  final bool enabled;
  final ValueChanged<WorkflowMatrixAxis?> onChanged;

  /// `${{ platforms }}` for `platform`, `${{ flavors }}` for `flavor`.
  String get _reference => '\${{ ${name}s }}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final axis = this.axis;
    final values = axis?.values;
    final mode = axis == null
        ? _AxisMode.none
        : values == null
        ? _AxisMode.dispatch
        : _AxisMode.list;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 72, child: XpCode(name)),
          XpSegmented<_AxisMode>(
            value: mode,
            values: _AxisMode.values,
            labelOf: (mode) => switch (mode) {
              _AxisMode.none => l10n.workflowsAxisNone,
              _AxisMode.dispatch => l10n.workflowsAxisDispatch,
              _AxisMode.list => l10n.workflowsAxisList,
            },
            onChanged: enabled
                ? (mode) => onChanged(switch (mode) {
                    _AxisMode.none => null,
                    _AxisMode.dispatch => WorkflowMatrixAxis.placeholder(
                      name,
                      _reference,
                    ),
                    _AxisMode.list => WorkflowMatrixAxis.list(
                      name,
                      name == 'platform' ? platforms : const [],
                    ),
                  })
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: switch (mode) {
              _AxisMode.none => const SizedBox(),
              _AxisMode.dispatch => XpCode(
                axis!.reference!,
                color: context.xpColors.textSecondary,
              ),
              _AxisMode.list when name == 'platform' => Wrap(
                spacing: 8,
                children: [
                  for (final platform in {...platforms, ...values!})
                    XpChip(
                      label: platform,
                      selected: values.contains(platform),
                      onChanged: enabled
                          ? (on) => onChanged(
                              WorkflowMatrixAxis.list(name, [
                                for (final p in {...platforms, ...values})
                                  if (p == platform ? on : values.contains(p))
                                    p,
                              ]),
                            )
                          : null,
                    ),
                ],
              ),
              _AxisMode.list => BoundTextField(
                value: values!.join(', '),
                hint: l10n.workflowsAxisValuesHint,
                code: true,
                enabled: enabled,
                onChanged: (text) => onChanged(
                  WorkflowMatrixAxis.list(name, [
                    for (final value in text.split(','))
                      if (value.trim().isNotEmpty) value.trim(),
                  ]),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// "Add step": picks one of the engine's step types. While the engine
/// cannot give them, it is disabled and says why.
class _AddStep extends StatelessWidget {
  const new({required this.steps, required this.enabled, required this.onAdd});

  /// The engine's step types; `null` while they are not known.
  final List<StepType>? steps;
  final bool enabled;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final steps = this.steps;
    final button = XpButton(
      label: l10n.workflowsAddStep,
      icon: PhosphorIconsRegular.plus,
      kind: XpButtonKind.tertiary,
      size: XpButtonSize.small,
      onPressed: enabled && steps != null
          ? () async {
              final kind = await pickStepType(context, steps);
              if (kind != null) onAdd(kind);
            }
          : null,
    );
    if (steps != null) return button;
    return Tooltip(message: l10n.workflowsAddStepUnavailable, child: button);
  }
}

/// One step of a job: a row with its type, `if` and gate that opens to
/// edit them and its `with` values.
class StepEditor extends StatefulWidget {
  const new({
    required this.index,
    required this.count,
    required this.step,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
    this.schema,
    this.variables = const [],
    this.enabled = true,
    super.key,
  });

  final int index;
  final int count;
  final WorkflowStep step;
  final WorkflowSchema? schema;

  /// What the `if` field completes: the paths an expression reads.
  final List<String> variables;
  final bool enabled;
  final ValueChanged<WorkflowStep> onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  State<StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends State<StepEditor> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final step = widget.step;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        border: Border.all(
          color: _open ? colors.borderStrong : colors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: context.xpSizes.rowDefault,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    _open
                        ? PhosphorIconsRegular.caretDown
                        : PhosphorIconsRegular.caretRight,
                    size: context.xpSizes.iconXs,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.index + 1}',
                    style: type.code.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    step.kind.isEmpty ? '—' : step.kind,
                    style: type.code.copyWith(color: colors.textPrimary),
                  ),
                  if (step.gate case final gate?) ...[
                    const SizedBox(width: 8),
                    XpStatusLabel(
                      XpStatus.approvalPending,
                      l10n.gateAction(gate),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.condition == null ? '' : 'if ${step.condition}',
                      overflow: TextOverflow.ellipsis,
                      style: type.code.copyWith(color: colors.textSecondary),
                    ),
                  ),
                  OrderActions(
                    index: widget.index,
                    count: widget.count,
                    enabled: widget.enabled,
                    earlier: l10n.workflowsMoveEarlier,
                    later: l10n.workflowsMoveLater,
                    remove: l10n.workflowsRemoveStep,
                    onMove: widget.onMove,
                    onRemove: widget.onRemove,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const XpHairline(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _StepFields(
                step: step,
                schema: widget.schema,
                variables: widget.variables,
                enabled: widget.enabled,
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepFields extends StatelessWidget {
  const new({
    required this.step,
    required this.schema,
    required this.variables,
    required this.enabled,
    required this.onChanged,
  });

  final WorkflowStep step;
  final WorkflowSchema? schema;
  final List<String> variables;
  final bool enabled;
  final ValueChanged<WorkflowStep> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final schema = this.schema;
    String? orNull(String text) => text.trim().isEmpty ? null : text;
    final kinds = {...?schema?.steps.map((s) => s.kind), step.kind}.toList();
    final known = schema?.steps.where((s) => s.kind == step.kind).firstOrNull;
    final typed = {
      for (final key in known?.keys ?? const <StepKeySchema>[]) key.name: key,
    };
    final keys = {...?known?.withKeys, ...typed.keys, ...step.withValues.keys};
    final gates = <String?>{null, ...?schema?.gates, step.gate}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: schema == null
                  ? BoundTextField(
                      label: l10n.workflowsStepKind,
                      value: step.kind,
                      code: true,
                      enabled: enabled,
                      onChanged: (text) =>
                          onChanged(step.copyWith(kind: text.trim())),
                    )
                  : _Labelled(
                      label: l10n.workflowsStepKind,
                      child: XpSelect<String>(
                        value: step.kind,
                        values: kinds,
                        labelOf: (kind) => kind,
                        code: true,
                        onChanged: enabled
                            ? (kind) => onChanged(step.copyWith(kind: kind))
                            : null,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            _Labelled(
              label: l10n.workflowsGate,
              child: XpSelect<String?>(
                value: step.gate,
                values: gates,
                labelOf: (gate) =>
                    gate == null ? l10n.workflowsNoGate : l10n.gateAction(gate),
                onChanged: enabled
                    ? (gate) => onChanged(step.copyWith(gate: () => gate))
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        BoundTextField(
          label: l10n.workflowsCondition,
          value: step.condition ?? '',
          hint: l10n.workflowsConditionHint,
          code: true,
          enabled: enabled,
          completions: variables,
          onChanged: (text) =>
              onChanged(step.copyWith(condition: () => orNull(text))),
        ),
        if (keys.isNotEmpty) ...[
          const SizedBox(height: 12),
          XpSectionLabel(l10n.workflowsWith),
          const SizedBox(height: 6),
          for (final key in keys)
            Padding(
              key: ValueKey(('with', key)),
              padding: const EdgeInsets.only(bottom: 6),
              child: _WithField(
                name: key,
                schema: typed[key],
                given: step.withValues.containsKey(key),
                value: step.withValues[key],
                enabled: enabled,
                onChanged: (values) => onChanged(
                  step.copyWith(withValues: values(step.withValues)),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Labelled extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [XpSectionLabel(label), const SizedBox(height: 6), child],
  );
}

/// [values] with [key] set to the YAML [text] in its place (at the end if
/// new), or without [key] when [text] is blank.
Map<String, Object?> _withValue(
  Map<String, Object?> values,
  String key,
  String text,
) {
  final blank = text.trim().isEmpty;
  return {
    for (final MapEntry(key: k, :value) in values.entries)
      if (k != key) k: value else if (!blank) k: parseYamlValue(text),
    if (!blank && !values.containsKey(key)) key: parseYamlValue(text),
  };
}

/// One key of `with`, edited by its type: On and Off for a boolean, a menu
/// for a string with options, chips for a list with options, YAML text for
/// the rest and for a placeholder. A key the step type needs is marked, and
/// says so while it is missing.
class _WithField extends StatelessWidget {
  const new({
    required this.name,
    required this.schema,
    required this.given,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String name;

  /// What the engine says of the key; `null` for one it does not know.
  final StepKeySchema? schema;
  final bool given;
  final Object? value;
  final bool enabled;

  /// Reports the change as a function of the values of `with`.
  final ValueChanged<Map<String, Object?> Function(Map<String, Object?>)>
  onChanged;

  void _set(Object? value) =>
      onChanged((values) => _withTyped(values, name, value));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final schema = this.schema;
    final value = this.value;
    final placeholder = value is String && value.contains(r'${{');
    final options = schema?.options;
    final defaultLabel = schema?.defaultValue == null
        ? l10n.workflowsKeyDefault
        : l10n.workflowsKeyDefaultValue(formatYamlValue(schema!.defaultValue));
    final flag = value is bool ? value : null;
    final choice = value is String ? value : null;
    final chosen = value is List ? value : const <Object?>[];
    final field = switch (schema?.type) {
      _ when placeholder || schema == null => _text(context),
      StepKeyType.boolean when value == null || value is bool =>
        XpSegmented<bool?>(
          value: flag,
          values: const [null, true, false],
          labelOf: (on) => switch (on) {
            null => defaultLabel,
            true => l10n.workflowsOn,
            false => l10n.workflowsOff,
          },
          onChanged: enabled ? _set : null,
        ),
      StepKeyType.string
          when options != null && (value == null || value is String) =>
        XpSelect<String?>(
          value: choice,
          values: [
            null,
            ...options,
            ?(options.contains(choice) ? null : choice),
          ],
          labelOf: (option) => option ?? defaultLabel,
          code: true,
          onChanged: enabled ? _set : null,
        ),
      StepKeyType.list
          when options != null && (value == null || value is List) =>
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in options)
              XpChip(
                label: option,
                selected: chosen.contains(option),
                onChanged: enabled
                    ? (on) => _set([
                        for (final o in options)
                          if (o == option ? on : chosen.contains(o)) o,
                      ])
                    : null,
              ),
          ],
        ),
      _ => _text(context),
    };
    final missing = (schema?.required ?? false) && !given;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Tooltip(
              message: schema?.description ?? '',
              child: Row(
                children: [
                  Flexible(child: XpCode(name)),
                  if (schema?.required ?? false)
                    Text(
                      ' *',
                      style: context.xpType.code.copyWith(
                        color: colors.negativeDefault,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field,
              if (missing)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.workflowsKeyNeeded,
                    style: context.xpType.caption.copyWith(
                      color: colors.negativeDefault,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _text(BuildContext context) => BoundTextField(
    value: given ? formatYamlValue(value) : '',
    hint: schema?.description ?? context.l10n.workflowsWithHint,
    code: true,
    enabled: enabled,
    onChanged: (text) => onChanged((values) => _withValue(values, name, text)),
  );
}

/// [values] with [key] set to [value] in its place (at the end if new), or
/// without [key] when [value] is `null`.
Map<String, Object?> _withTyped(
  Map<String, Object?> values,
  String key,
  Object? value,
) => {
  for (final MapEntry(key: k, value: v) in values.entries)
    if (k != key) k: v else k: ?value,
  if (value != null && !values.containsKey(key)) key: value,
};

final _inputNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// One input of the workflow: its name, type and whether a dispatch must
/// give it, what it is for, the options of a choice, and its default.
class InputEditor extends StatelessWidget {
  const new({
    required this.input,
    required this.onChanged,
    required this.onRemove,
    this.enabled = true,
    super.key,
  });

  final WorkflowInput input;
  final bool enabled;
  final ValueChanged<WorkflowInput> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final input = this.input;
    final defaultValue = input.defaultValue;
    final options = input.options ?? const <String>[];
    String? orNull(String text) => text.trim().isEmpty ? null : text;
    final badName = !_inputNamePattern.hasMatch(input.name);
    final defaultField = switch (input.type) {
      InputType.boolean when defaultValue == null || defaultValue is bool =>
        XpSegmented<bool?>(
          value: defaultValue is bool ? defaultValue : null,
          values: const [null, true, false],
          labelOf: (on) => switch (on) {
            null => l10n.workflowsInputNoDefault,
            true => l10n.workflowsOn,
            false => l10n.workflowsOff,
          },
          onChanged: enabled
              ? (on) => onChanged(input.copyWith(defaultValue: () => on))
              : null,
        ),
      InputType.choice when options.isNotEmpty => XpSelect<String?>(
        value: defaultValue is String && options.contains(defaultValue)
            ? defaultValue
            : null,
        values: [null, ...options],
        labelOf: (option) => option ?? l10n.workflowsInputNoDefault,
        code: true,
        onChanged: enabled
            ? (option) => onChanged(input.copyWith(defaultValue: () => option))
            : null,
      ),
      _ => BoundTextField(
        value: defaultValue == null ? '' : formatYamlValue(defaultValue),
        hint: l10n.workflowsWithHint,
        code: true,
        enabled: enabled,
        onChanged: (text) => onChanged(
          input.copyWith(
            defaultValue: () =>
                text.trim().isEmpty ? null : parseYamlValue(text),
          ),
        ),
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: BoundTextField(
                  label: l10n.workflowsInputName,
                  value: input.name,
                  code: true,
                  enabled: enabled,
                  onChanged: (text) =>
                      onChanged(input.copyWith(name: text.trim())),
                ),
              ),
              const SizedBox(width: 12),
              _Labelled(
                label: l10n.workflowsInputType,
                child: XpSelect<InputType?>(
                  value: input.type,
                  values: const [null, ...InputType.values],
                  labelOf: (type) => _typeLabel(l10n, type),
                  onChanged: enabled
                      ? (type) => onChanged(
                          input.copyWith(
                            type: () => type,
                            options: () => type == InputType.choice
                                ? input.options ?? const []
                                : null,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: XpChip(
                  label: l10n.workflowsInputRequired,
                  selected: input.required,
                  onChanged: enabled
                      ? (on) => onChanged(
                          input.copyWith(
                            required: on,
                            defaultValue: on ? () => null : null,
                          ),
                        )
                      : null,
                ),
              ),
              RowAction(
                icon: PhosphorIconsRegular.trash,
                tooltip: l10n.workflowsRemoveInput,
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
          if (badName)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.workflowsInputNameInvalid,
                style: context.xpType.caption.copyWith(
                  color: colors.negativeDefault,
                ),
              ),
            ),
          const SizedBox(height: 12),
          BoundTextField(
            label: l10n.workflowsInputDescription,
            value: input.description ?? '',
            enabled: enabled,
            onChanged: (text) =>
                onChanged(input.copyWith(description: () => orNull(text))),
          ),
          if (input.type == InputType.choice) ...[
            const SizedBox(height: 12),
            BoundTextField(
              label: l10n.workflowsInputOptions,
              value: options.join(', '),
              hint: l10n.workflowsInputOptionsHint,
              code: true,
              enabled: enabled,
              onChanged: (text) => onChanged(
                input.copyWith(
                  options: () => [
                    for (final option in text.split(','))
                      if (option.trim().isNotEmpty) option.trim(),
                  ],
                ),
              ),
            ),
          ],
          if (!input.required) ...[
            const SizedBox(height: 12),
            _Labelled(label: l10n.workflowsInputDefault, child: defaultField),
          ],
        ],
      ),
    );
  }

  static String _typeLabel(AppLocalizations l10n, InputType? type) =>
      switch (type) {
        null => l10n.workflowsInputTypeAny,
        InputType.string => l10n.workflowsInputTypeString,
        InputType.boolean => l10n.workflowsInputTypeBoolean,
        InputType.choice => l10n.workflowsInputTypeChoice,
        InputType.json => l10n.workflowsInputTypeJson,
        InputType.release => l10n.workflowsInputTypeRelease,
      };
}
