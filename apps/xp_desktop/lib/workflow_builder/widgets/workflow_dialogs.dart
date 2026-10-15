import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Asks for the name of a new workflow, offering [initial]; `null` when the
/// owner cancels.
Future<String?> askWorkflowName(BuildContext context, {String? initial}) =>
    showDialog<String>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => WorkflowNameDialog(initial: initial ?? ''),
    );

/// Asks before dropping the unsaved changes to [name]; `true` to drop them.
/// Return does nothing, Escape keeps them.
Future<bool> confirmDiscard(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => DiscardChangesDialog(name: name),
    ) ??
    false;

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
  const new({required this.initial, super.key});

  final String initial;

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

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _BuilderDialog(
      title: l10n.workflowsNameTitle,
      children: [
        XpTextField(
          label: l10n.workflowsName,
          controller: _name,
          code: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.workflowsNameBody,
          style: context.xpType.caption.copyWith(
            color: context.xpColors.textSecondary,
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
              onPressed: _name.text.trim().isEmpty ? null : _save,
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
