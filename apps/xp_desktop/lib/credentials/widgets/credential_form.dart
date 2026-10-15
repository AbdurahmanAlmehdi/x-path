import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// A flavor of an app of the project, as a credential addresses it.
typedef FlavorTarget = ({String app, String appName, String flavor});

/// The flavors of [project], `default` for an app without flavors.
List<FlavorTarget> flavorTargets(Project project) => [
  for (final app in project.profile.apps)
    if (app.flavors.isEmpty)
      (app: app.path, appName: app.name, flavor: 'default')
    else
      for (final flavor in app.flavors)
        (app: app.path, appName: app.name, flavor: flavor.name),
];

/// The name of a credential kind.
String credentialKindLabel(AppLocalizations l10n, CredentialKind kind) =>
    switch (kind) {
      CredentialKind.ascKey => l10n.kindAscKey,
      CredentialKind.appleId => l10n.kindAppleId,
      CredentialKind.playSa => l10n.kindPlaySa,
      CredentialKind.firebaseSa => l10n.kindFirebaseSa,
      CredentialKind.keystore => l10n.kindKeystore,
      CredentialKind.shorebird => l10n.kindShorebird,
      CredentialKind.github => l10n.kindGithub,
      CredentialKind.slack => l10n.kindSlack,
    };

/// How a field is filled.
enum _Input { text, secret, multiline, file }

/// One secret field of a kind, named as `SaveCredentialRequest` sends it.
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

/// The fields of each kind (`openapi.yaml`, `SaveCredentialRequest`).
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
  CredentialKind.github: [_field('token', (l) => l.fieldToken, _Input.secret)],
  CredentialKind.slack: [_field('webhookUrl', (l) => l.fieldWebhookUrl)],
};

/// The credentials editor's form: a flavor, a kind and the secret fields of
/// that kind. Text files (a `.p8` key, a service account) can be read into
/// their field; a keystore is read as bytes and sent base64.
class CredentialForm extends StatefulWidget {
  const new({
    required this.project,
    required this.onSubmit,
    required this.onCancel,
    this.saving = false,
    this.error,
    this.target,
    this.kind,
    super.key,
  });

  final Project project;
  final ValueChanged<SaveCredentialRequest> onSubmit;
  final VoidCallback onCancel;
  final bool saving;

  /// Why the last save was refused.
  final String? error;

  /// The flavor to start with (replacing a credential).
  final FlavorTarget? target;

  /// The kind to start with (replacing a credential).
  final CredentialKind? kind;

  @override
  State<CredentialForm> createState() => _CredentialFormState();
}

class _CredentialFormState extends State<CredentialForm> {
  late final List<FlavorTarget> _targets = flavorTargets(widget.project);
  late FlavorTarget _target = widget.target ?? _targets.first;
  late CredentialKind _kind = widget.kind ?? CredentialKind.ascKey;
  final _controllers = <String, TextEditingController>{};
  final _files = <String, String>{};

  TextEditingController _controller(String name) =>
      _controllers.putIfAbsent(name, TextEditingController.new);

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(_Field field) => field.input == _Input.file
      ? _files[field.name] ?? ''
      : _controller(field.name).text.trim();

  bool get _complete => _fields[_kind]!.every(
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
          file.bytes.length,
        );
      } else {
        _controller(field.name).text = utf8.decode(
          file.bytes,
          allowMalformed: true,
        );
      }
    });
  }

  void _submit() => widget.onSubmit(
    SaveCredentialRequest(
      app: _target.app,
      flavor: _target.flavor,
      kind: _kind,
      material: {
        for (final field in _fields[_kind]!)
          if (_value(field).isNotEmpty) field.name: _value(field),
      },
    ),
  );

  String _targetLabel(FlavorTarget target) =>
      widget.project.profile.apps.length > 1
      ? '${target.appName} · ${target.flavor}'
      : target.flavor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.credentialFormTitle,
            style: type.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.credentialFormHelp,
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              XpSectionLabel(l10n.fieldFlavor),
              const SizedBox(width: 8),
              XpSelect<FlavorTarget>(
                key: const Key('credentialForm.flavor'),
                value: _target,
                values: _targets,
                labelOf: _targetLabel,
                code: true,
                onChanged: (target) => setState(() => _target = target),
              ),
              const SizedBox(width: 20),
              XpSectionLabel(l10n.fieldKind),
              const SizedBox(width: 8),
              XpSelect<CredentialKind>(
                key: const Key('credentialForm.kind'),
                value: _kind,
                values: CredentialKind.values,
                labelOf: (kind) => credentialKindLabel(l10n, kind),
                onChanged: (kind) => setState(() => _kind = kind),
              ),
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
                label: l10n.credentialFormSave,
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
