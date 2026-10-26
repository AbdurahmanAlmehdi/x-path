import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/credentials/widgets/credential_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// How a field is filled.
enum _Input { text, secret, multiline, file }

/// One secret field of a kind, named as the API reads it.
typedef _Field = ({
  String name,
  String Function(AppLocalizations l10n) label,
  _Input input,
  bool optional,
});

_Field _field(
  String name,
  String Function(AppLocalizations l10n) label, [
  _Input input = _Input.text,
  bool optional = false,
]) => (name: name, label: label, input: input, optional: optional);

/// The secret fields of each named kind (`openapi.yaml`,
/// `CreateCredentialRequest`). An App Store Connect key also has its key
/// type, chosen apart.
final Map<CredentialKind, List<_Field>> _fields = {
  CredentialKind.ascKey: [
    _field('keyId', (l) => l.fieldKeyId),
    _field('issuerId', (l) => l.fieldIssuerId),
    _field('privateKey', (l) => l.fieldPrivateKey, _Input.multiline),
  ],
  CredentialKind.appleId: [
    _field('appleId', (l) => l.fieldAppleId),
    _field('password', (l) => l.fieldAppPassword, _Input.secret),
  ],
  CredentialKind.appleDistribution: [
    _field('privateKey', (l) => l.fieldSigningKey, _Input.multiline),
    _field('certificate', (l) => l.fieldCertificate, _Input.file),
  ],
  CredentialKind.playSa: [
    _field('serviceAccount', (l) => l.fieldServiceAccount, _Input.multiline),
  ],
  CredentialKind.firebaseSa: [
    _field('serviceAccount', (l) => l.fieldServiceAccount, _Input.multiline),
  ],
  CredentialKind.keystore: [
    _field('keystore', (l) => l.fieldKeystore, _Input.file),
    _field('storePassword', (l) => l.fieldStorePassword, _Input.secret),
    _field('keyAlias', (l) => l.fieldKeyAlias),
    _field('keyPassword', (l) => l.fieldKeyPassword, _Input.secret, true),
  ],
  CredentialKind.shorebird: [
    _field('token', (l) => l.fieldToken, _Input.secret),
  ],
  CredentialKind.slack: [_field('webhookUrl', (l) => l.fieldWebhookUrl)],
};

/// The types of App Store Connect API key (`keyKind`).
const _keyKinds = ['team', 'individual'];

/// The form of a named credential: its name, its kind and the secret fields
/// of the kind to add one; the secret fields alone to replace the secret of
/// one. Text files (a `.p8` key, a service account) can be read into their
/// field; a keystore is read as bytes and sent base64. A secret is never
/// shown again once saved.
class CredentialForm extends StatefulWidget {
  /// The form that adds a credential, of [kind] to start with (and only of
  /// it with [lockKind]).
  const new({
    required ValueChanged<CreateCredentialRequest> this.onCreate,
    required this.onCancel,
    this.kind,
    this.lockKind = false,
    this.saving = false,
    this.error,
    this.submitLabel,
    super.key,
  }) : replacing = null,
       onReplace = null;

  /// The form that replaces the secret of [replacing], whose kind decides
  /// the fields.
  const new replace({
    required NamedCredential this.replacing,
    required ValueChanged<ReplaceCredentialRequest> this.onReplace,
    required this.onCancel,
    this.saving = false,
    this.error,
    super.key,
  }) : onCreate = null,
       kind = null,
       lockKind = true,
       submitLabel = null;

  final ValueChanged<CreateCredentialRequest>? onCreate;
  final ValueChanged<ReplaceCredentialRequest>? onReplace;
  final VoidCallback onCancel;

  /// The credential whose secret the form replaces.
  final NamedCredential? replacing;

  /// The kind to start with.
  final CredentialKind? kind;

  /// Whether the kind is fixed.
  final bool lockKind;
  final bool saving;

  /// Why the last save was refused.
  final String? error;

  /// The label of the save button, "Check and save" when `null`.
  final String? submitLabel;

  @override
  State<CredentialForm> createState() => _CredentialFormState();
}

class _CredentialFormState extends State<CredentialForm> {
  late CredentialKind _kind =
      widget.replacing?.kind ?? widget.kind ?? CredentialKind.ascKey;
  final _name = TextEditingController();
  final _controllers = <String, TextEditingController>{};
  final _files = <String, String>{};
  String _keyKind = _keyKinds.first;

  bool get _creating => widget.replacing == null;

  TextEditingController _controller(String name) =>
      _controllers.putIfAbsent(name, TextEditingController.new);

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(_Field field) => field.input == _Input.file
      ? _files[field.name] ?? ''
      : _controller(field.name).text.trim();

  String get _nameValue => _name.text.trim();

  bool get _complete =>
      (!_creating ||
          (_nameValue.isNotEmpty &&
              _nameValue.length <= maxCredentialNameLength)) &&
      _fields[_kind]!.every(
        (field) => field.optional || _value(field).isNotEmpty,
      );

  Future<void> _pick(_Field field) async {
    final file = await context.read<AppServices>().pickFile();
    if (file == null) return;
    setState(() {
      if (field.input == _Input.file) {
        _files[field.name] = base64Encode(file.bytes);
        _controller(field.name).text = context.l10n.fieldFileChosen(
          file.name,
          formatSize(file.bytes.length),
        );
      } else {
        _controller(field.name).text = utf8.decode(
          file.bytes,
          allowMalformed: true,
        );
      }
    });
  }

  void _submit() {
    final material = <String, dynamic>{
      for (final field in _fields[_kind]!)
        if (_value(field).isNotEmpty) field.name: _value(field),
      if (_kind == CredentialKind.ascKey) 'keyKind': _keyKind,
    };
    if (widget.onCreate case final onCreate?) {
      onCreate(
        CreateCredentialRequest(
          name: _nameValue,
          kind: _kind,
          material: material,
        ),
      );
    } else {
      widget.onReplace!(ReplaceCredentialRequest(material));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final replacing = widget.replacing;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            replacing == null
                ? l10n.credentialFormTitle
                : l10n.credentialFormReplaceTitle(replacing.name),
            style: type.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            replacing == null
                ? l10n.credentialFormHelp
                : l10n.credentialFormReplaceHelp,
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_creating) ...[
            XpTextField(
              key: const Key('credentialForm.name'),
              label: l10n.fieldCredentialName,
              hint: l10n.fieldCredentialNameHint,
              controller: _name,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              XpSectionLabel(l10n.fieldKind),
              const SizedBox(width: 8),
              if (widget.lockKind)
                Text(
                  credentialKindLabel(l10n, _kind),
                  style: type.bodyStrong.copyWith(color: colors.textPrimary),
                )
              else
                XpSelect<CredentialKind>(
                  key: const Key('credentialForm.kind'),
                  value: _kind,
                  values: namedKinds,
                  labelOf: (kind) => credentialKindLabel(l10n, kind),
                  onChanged: (kind) => setState(() => _kind = kind),
                ),
              if (_kind == CredentialKind.ascKey) ...[
                const SizedBox(width: 20),
                XpSectionLabel(l10n.fieldKeyKind),
                const SizedBox(width: 8),
                XpSelect<String>(
                  key: const Key('credentialForm.keyKind'),
                  value: _keyKind,
                  values: _keyKinds,
                  labelOf: (kind) => kind == 'team'
                      ? l10n.keyKindTeam
                      : l10n.keyKindIndividual,
                  onChanged: (kind) => setState(() => _keyKind = kind),
                ),
              ],
            ],
          ),
          for (final field in _fields[_kind]!) ...[
            const SizedBox(height: 12),
            XpTextField(
              key: Key('credentialForm.${field.name}'),
              label: field.label(l10n),
              controller: _controller(field.name),
              obscure: field.input == _Input.secret,
              code: true,
              enabled: field.input != _Input.file,
              maxLines: field.input == _Input.multiline ? 6 : 1,
              onChanged: (_) => setState(() {}),
              trailing:
                  field.input == _Input.multiline || field.input == _Input.file
                  ? XpButton(
                      label: l10n.fieldChooseFile,
                      onPressed: () => _pick(field),
                    )
                  : null,
            ),
          ],
          if (widget.error case final error?) ...[
            const SizedBox(height: 12),
            XpMessage(XpStatus.credentialExpired, l10n.credentialFailed(error)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              XpButton(
                label: l10n.credentialFormCancel,
                kind: XpButtonKind.tertiary,
                onPressed: widget.onCancel,
              ),
              const SizedBox(width: 8),
              XpButton(
                label: widget.submitLabel ?? l10n.credentialFormSave,
                kind: XpButtonKind.primary,
                busy: widget.saving,
                onPressed: _complete ? _submit : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
