import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/bloc/credentials_bloc.dart';
import 'package:xp_desktop/credentials/bloc/project_credentials_bloc.dart';
import 'package:xp_desktop/credentials/view/flavor_credentials_sheet.dart';
import 'package:xp_desktop/credentials/widgets/credential_dialogs.dart';
import 'package:xp_desktop/credentials/widgets/credential_form.dart';
import 'package:xp_desktop/credentials/widgets/credential_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The credentials of the engine: the named credentials, each with the
/// result of its last check and the flavors that use it; the form to add
/// one or replace its secret; and the flavors of one project with the
/// credentials they use.
class CredentialsPage extends StatelessWidget {
  const new({this.projectId, super.key});

  /// The project whose flavors to show; the first one when `null`.
  final String? projectId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        CredentialsBloc(credentials: context.read<CredentialsRepository>())
          ..add(const CredentialsSubscriptionRequested()),
    child: CredentialsView(projectId: projectId),
  );
}

/// What the form is open for: adding a credential, or replacing the secret
/// of `replacing`.
typedef _FormMode = ({NamedCredential? replacing});

class CredentialsView extends StatefulWidget {
  const new({this.projectId, super.key});

  final String? projectId;

  @override
  State<CredentialsView> createState() => _CredentialsViewState();
}

class _CredentialsViewState extends State<CredentialsView> {
  _FormMode? _form;

  void _open([NamedCredential? replacing]) {
    context.read<CredentialsBloc>().add(const CredentialFormReset());
    setState(() => _form = (replacing: replacing));
  }

  void _close() => setState(() => _form = null);

  Future<void> _rename(NamedCredential credential) async {
    final bloc = context.read<CredentialsBloc>();
    final name = await askCredentialName(context, credential);
    if (name != null) bloc.add(CredentialRenameRequested(credential.id, name));
  }

  Future<void> _delete(
    NamedCredential credential,
    List<CredentialUsage> usedBy,
  ) async {
    final bloc = context.read<CredentialsBloc>();
    if (await confirmDeleteCredential(context, credential, usedBy)) {
      bloc.add(
        CredentialDeleteRequested(credential.id, force: usedBy.isNotEmpty),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canCommand = context.canCommand;
    return MultiBlocListener(
      listeners: [
        BlocListener<CredentialsBloc, CredentialsState>(
          listenWhen: (previous, current) =>
              previous.save != current.save &&
              current.save == CredentialSaveStatus.saved,
          listener: (context, state) {
            _close();
            context.read<ToastCubit>().show(l10n.credentialSavedToast);
          },
        ),
        BlocListener<CredentialsBloc, CredentialsState>(
          listenWhen: (previous, current) =>
              current.checked != null && previous.checked != current.checked,
          listener: (context, state) {
            final checked = state.checked!;
            context.read<ToastCubit>().show(
              l10n.credentialCheckedToast(
                checked.name,
                credentialStatusLabel(l10n, checked.status).$2,
              ),
            );
          },
        ),
        BlocListener<CredentialsBloc, CredentialsState>(
          listenWhen: (previous, current) =>
              current.inUse != null && previous.inUse != current.inUse,
          listener: (context, state) {
            final conflict = state.inUse!;
            final credential = state.credentials
                .where((credential) => credential.id == conflict.credentialId)
                .firstOrNull;
            if (credential != null) {
              unawaited(_delete(credential, conflict.usedBy));
            }
          },
        ),
      ],
      child: BlocBuilder<CredentialsBloc, CredentialsState>(
        builder: (context, state) {
          final form = _form;
          final replacing = form?.replacing;
          final bloc = context.read<CredentialsBloc>();
          final saving = state.save == CredentialSaveStatus.saving;
          final saveError = state.save == CredentialSaveStatus.failed
              ? state.saveError
              : null;
          return ShellPage(
            title: l10n.credentialsTitle,
            cached: state.cached,
            subtitle: l10n.credentialsSubtitle,
            actions: [
              XpButton(
                label: l10n.credentialsAdd,
                kind: XpButtonKind.primary,
                icon: PhosphorIconsRegular.plus,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed: canCommand && form == null ? _open : null,
              ),
            ],
            // A column, not a list: the flavors section keeps its bloc when
            // the form or a message appears above it.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (form != null) ...[
                    if (replacing == null)
                      CredentialForm(
                        key: const Key('credentials.create'),
                        saving: saving,
                        error: saveError,
                        onCancel: _close,
                        onCreate: (request) =>
                            bloc.add(CredentialCreateRequested(request)),
                      )
                    else
                      CredentialForm.replace(
                        key: ValueKey(replacing.id),
                        replacing: replacing,
                        saving: saving,
                        error: saveError,
                        onCancel: _close,
                        onReplace: (request) => bloc.add(
                          CredentialReplaceRequested(replacing.id, request),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                  if (state.error case final error? when !state.loaded) ...[
                    XpErrorState(
                      error,
                      onRetry: () =>
                          bloc.add(const CredentialsSubscriptionRequested()),
                    ),
                    const SizedBox(height: 12),
                  ] else if (state.error case final error?) ...[
                    XpMessage.error(error),
                    const SizedBox(height: 12),
                  ],
                  _CredentialTable(
                    state: state,
                    canCommand: canCommand,
                    onAdd: form == null ? _open : null,
                    onRename: _rename,
                    onReplace: _open,
                    onDelete: (credential) =>
                        _delete(credential, credential.usedBy),
                  ),
                  const SizedBox(height: 28),
                  _FlavorsSection(projectId: widget.projectId),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CredentialTable extends StatelessWidget {
  const new({
    required this.state,
    required this.canCommand,
    required this.onAdd,
    required this.onRename,
    required this.onReplace,
    required this.onDelete,
  });

  final CredentialsState state;
  final bool canCommand;

  /// Opens the form of a new credential; `null` while a form is open.
  final VoidCallback? onAdd;
  final ValueChanged<NamedCredential> onRename;
  final ValueChanged<NamedCredential> onReplace;
  final ValueChanged<NamedCredential> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    if (state.loaded && state.credentials.isEmpty) {
      return XpPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.credentialsEmpty,
                style: type.body.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            XpButton(
              label: l10n.credentialsAdd,
              icon: PhosphorIconsRegular.plus,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed: canCommand ? onAdd : null,
            ),
          ],
        ),
      );
    }
    final bloc = context.read<CredentialsBloc>();
    final columns = [
      l10n.credentialsColumnName,
      l10n.credentialsColumnKind,
      l10n.credentialsColumnAccount,
      l10n.credentialsColumnStatus,
      l10n.credentialsColumnUsedBy,
      '',
    ];
    return XpPanel(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(),
          3: FlexColumnWidth(1.5),
          4: FlexColumnWidth(0.7),
          5: IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final column in columns) _Cell(XpSectionLabel(column)),
            ],
          ),
          for (final credential in state.credentials)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              children: [
                _Cell(
                  Text(
                    credential.name,
                    style: type.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                _Cell(
                  Text(
                    credentialKindLabel(l10n, credential.kind),
                    style: type.body.copyWith(color: colors.textPrimary),
                  ),
                ),
                _Cell(
                  credential.account == null
                      ? Text(
                          '—',
                          style: type.code.copyWith(color: colors.textTertiary),
                        )
                      : XpCode(credential.account!),
                ),
                _Cell(
                  CredentialStatusView(
                    credential.status,
                    message: credential.message,
                    fix: credential.fix,
                  ),
                ),
                _Cell(_UsedBy(credential.usedBy)),
                _Cell(
                  Row(
                    key: ValueKey(credential.id),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      XpButton(
                        label: l10n.credentialsVerify,
                        size: XpButtonSize.small,
                        busy: state.busy == credential.id,
                        onPressed: canCommand
                            ? () => bloc.add(
                                CredentialVerifyRequested(credential.id),
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      for (final (label, action) in [
                        (l10n.credentialsRename, onRename),
                        (l10n.credentialsReplace, onReplace),
                        (l10n.credentialsDelete, onDelete),
                      ]) ...[
                        XpButton(
                          label: label,
                          size: XpButtonSize.small,
                          kind: XpButtonKind.tertiary,
                          onPressed: canCommand
                              ? () => action(credential)
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// How many flavors use a credential; which ones on hover.
class _UsedBy extends StatelessWidget {
  const new(this.usedBy);

  final List<CredentialUsage> usedBy;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final text = Text(
      context.l10n.credentialsUsedBy(usedBy.length),
      style: context.xpType.body.copyWith(
        color: usedBy.isEmpty ? colors.textTertiary : colors.textPrimary,
        decoration: usedBy.isEmpty ? null : TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: colors.textTertiary,
      ),
    );
    if (usedBy.isEmpty) return text;
    return Tooltip(message: usedBy.map(usageLabel).join('\n'), child: text);
  }
}

/// The flavors of one project, with the credential each uses of each kind.
class _FlavorsSection extends StatelessWidget {
  const new({required this.projectId});

  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projects = context.watch<ProjectsBloc>().state;
    final project =
        projects.byId(projectId) ??
        (projects.projects.isEmpty ? null : projects.projects.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.credentialsFlavorsTitle,
              style: context.xpType.title.copyWith(
                color: context.xpColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            if (project != null)
              XpSelect<Project>(
                key: const Key('credentials.project'),
                value: project,
                values: projects.projects,
                labelOf: (project) => project.fullName,
                onChanged: (project) => context.read<ShellCubit>().show(
                  CredentialsDestination(project.id),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.credentialsFlavorsHelp,
          style: context.xpType.body.copyWith(
            color: context.xpColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (project == null)
          XpMessage(XpStatus.scanInfo, l10n.credentialsNoProject)
        else
          BlocProvider(
            key: ValueKey(project.id),
            create: (context) => ProjectCredentialsBloc(
              projects: context.read<ProjectsRepository>(),
              credentials: context.read<CredentialsRepository>(),
            )..add(ProjectCredentialsSubscriptionRequested(project.id)),
            child: _FlavorTable(project: project),
          ),
      ],
    );
  }
}

class _FlavorTable extends StatelessWidget {
  const new({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<ProjectCredentialsBloc>().state;
    final targets = flavorTargets(project);
    final severalApps = project.profile.apps.length > 1;
    if (targets.isEmpty) {
      return XpMessage(XpStatus.scanWarning, l10n.scanNoApps);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error case final error?) ...[
          XpErrorState(
            error,
            onRetry: () => context.read<ProjectCredentialsBloc>().add(
              ProjectCredentialsSubscriptionRequested(project.id),
            ),
          ),
          const SizedBox(height: 12),
        ],
        XpPanel(
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(0.8),
              1: FlexColumnWidth(2.6),
              2: FlexColumnWidth(0.8),
              3: IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  for (final column in [
                    l10n.credentialsColumnFlavor,
                    l10n.credentialsColumnAssigned,
                    l10n.credentialsColumnStatus,
                    '',
                  ])
                    _Cell(XpSectionLabel(column)),
                ],
              ),
              for (final target in targets)
                _flavorRow(
                  context,
                  target,
                  state.of(target.app, target.flavor),
                  severalApps: severalApps,
                ),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _flavorRow(
    BuildContext context,
    FlavorTarget target,
    List<Credential> mine, {
    required bool severalApps,
  }) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final status = worstStatus(mine.map((credential) => credential.status));
    return TableRow(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      children: [
        _Cell(
          XpCode(
            severalApps
                ? '${target.appName} · ${target.flavor}'
                : target.flavor,
          ),
        ),
        _Cell(
          mine.isEmpty
              ? Text(
                  l10n.credentialsNoneAssigned,
                  style: type.body.copyWith(color: colors.textTertiary),
                )
              : Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final credential in mine)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          XpStatusIcon(
                            credentialStatusLabel(l10n, credential.status).$1,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${credentialKindLabel(l10n, credential.kind)}: ',
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          Text(
                            credential.name ?? credential.id,
                            style: type.body.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        _Cell(
          status == null
              ? XpStatusLabel(
                  XpStatus.credentialMissing,
                  l10n.ledgerCredentialsNone,
                )
              : CredentialStatusView(status),
        ),
        _Cell(
          XpButton(
            label: l10n.credentialsManage,
            size: XpButtonSize.small,
            onPressed: () => showFlavorCredentialsSheet(
              context,
              project: project,
              target: target,
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const new(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 12, 8), child: child);
}
