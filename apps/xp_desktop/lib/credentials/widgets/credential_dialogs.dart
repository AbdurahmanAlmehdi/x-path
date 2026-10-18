import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/widgets/credential_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Asks for a new name for [credential]; `null` when the owner keeps it.
Future<String?> askCredentialName(
  BuildContext context,
  NamedCredential credential,
) => showDialog<String>(
  context: context,
  barrierColor: context.xpColors.scrimDefault,
  builder: (_) => RenameCredentialDialog(credential: credential),
);

/// Asks before deleting [credential], used by [usedBy]: `true` when the
/// owner confirms. When flavors use it, it lists them: they lose it.
/// Return does nothing, Escape keeps it.
Future<bool> confirmDeleteCredential(
  BuildContext context,
  NamedCredential credential,
  List<CredentialUsage> usedBy,
) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) =>
          DeleteCredentialDialog(credential: credential, usedBy: usedBy),
    ) ??
    false;

/// A small dialog of the Run Sheet: [title], [content], then the [actions].
class _CredentialDialog extends StatelessWidget {
  const new({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final List<Widget> content;
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
        width: 480,
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
              const SizedBox(height: 14),
              ...content,
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    action,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RenameCredentialDialog extends StatefulWidget {
  const new({required this.credential, super.key});

  final NamedCredential credential;

  @override
  State<RenameCredentialDialog> createState() => _RenameCredentialDialogState();
}

class _RenameCredentialDialogState extends State<RenameCredentialDialog> {
  late final _name = TextEditingController(text: widget.credential.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _value => _name.text.trim();

  bool get _valid =>
      _value.isNotEmpty &&
      _value.length <= maxCredentialNameLength &&
      _value != widget.credential.name;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CredentialDialog(
      title: l10n.renameCredentialTitle(widget.credential.name),
      content: [
        Text(
          l10n.renameCredentialHelp,
          style: context.xpType.body.copyWith(
            color: context.xpColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        XpTextField(
          key: const Key('renameCredential.name'),
          label: l10n.fieldCredentialName,
          controller: _name,
          onChanged: (_) => setState(() {}),
        ),
      ],
      actions: [
        XpButton(
          label: l10n.credentialFormCancel,
          size: XpButtonSize.large,
          onPressed: () => Navigator.of(context).pop(),
        ),
        XpButton(
          label: l10n.renameCredentialConfirm,
          kind: XpButtonKind.primary,
          size: XpButtonSize.large,
          onPressed: _valid ? () => Navigator.of(context).pop(_value) : null,
        ),
      ],
    );
  }
}

class DeleteCredentialDialog extends StatelessWidget {
  const new({required this.credential, required this.usedBy, super.key});

  final NamedCredential credential;
  final List<CredentialUsage> usedBy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    void close({required bool confirmed}) =>
        Navigator.of(context).pop(confirmed);
    Text point(String text) =>
        Text(text, style: type.body.copyWith(color: colors.textPrimary));
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter):
            DoNothingAndStopPropagationIntent(),
      },
      child: Focus(
        autofocus: true,
        child: _CredentialDialog(
          title: l10n.deleteCredentialTitle(credential.name),
          content: [
            point(l10n.deleteCredentialSecret),
            const SizedBox(height: 8),
            if (usedBy.isEmpty)
              point(l10n.deleteCredentialUnused)
            else ...[
              XpMessage(
                XpStatus.credentialMissing,
                l10n.deleteCredentialUsed(
                  usedBy.length,
                  credentialKindLabel(l10n, credential.kind),
                ),
              ),
              const SizedBox(height: 8),
              for (final usage in usedBy)
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: XpCode(usageLabel(usage)),
                ),
            ],
          ],
          actions: [
            XpButton(
              label: l10n.deleteCredentialKeep,
              size: XpButtonSize.large,
              onPressed: () => close(confirmed: false),
            ),
            XpButton(
              label: usedBy.isEmpty
                  ? l10n.deleteCredentialConfirm
                  : l10n.deleteCredentialConfirmInUse,
              kind: XpButtonKind.destructive,
              size: XpButtonSize.large,
              onPressed: () => close(confirmed: true),
            ),
          ],
        ),
      ),
    );
  }
}
