import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/bloc/credentials_bloc.dart';
import 'package:xp_desktop/credentials/widgets/credential_form.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The credentials editor: the credentials of one project, each with the
/// result of its last check, and the form to add or replace one.
class CredentialsPage extends StatelessWidget {
  const new({this.projectId, super.key});

  /// The project to show; the first one when `null`.
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projects = context.watch<ProjectsBloc>().state;
    final project =
        projects.byId(projectId) ??
        (projects.projects.isEmpty ? null : projects.projects.first);
    if (project == null) {
      return ShellPage(
        title: l10n.credentialsTitle,
        subtitle: l10n.credentialsSubtitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, l10n.credentialsNoProject),
        ),
      );
    }
    return BlocProvider(
      key: ValueKey(project.id),
      create: (context) =>
          CredentialsBloc(projects: context.read<ProjectsRepository>())
            ..add(CredentialsSubscriptionRequested(project.id)),
      child: CredentialsView(project: project, projects: projects.projects),
    );
  }
}

class CredentialsView extends StatefulWidget {
  const new({required this.project, required this.projects, super.key});

  final Project project;
  final List<Project> projects;

  @override
  State<CredentialsView> createState() => _CredentialsViewState();
}

class _CredentialsViewState extends State<CredentialsView> {
  /// The open form, and what it starts with.
  ({FlavorTarget? target, CredentialKind? kind})? _form;

  void _open({FlavorTarget? target, CredentialKind? kind}) {
    context.read<CredentialsBloc>().add(const CredentialFormReset());
    setState(() => _form = (target: target, kind: kind));
  }

  void _close() => setState(() => _form = null);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canCommand = context.canCommand;
    return BlocConsumer<CredentialsBloc, CredentialsState>(
      listenWhen: (previous, current) =>
          previous.save != current.save &&
          current.save == CredentialSaveStatus.saved,
      listener: (context, state) => _close(),
      builder: (context, state) {
        final form = _form;
        return ShellPage(
          title: l10n.credentialsTitle,
          subtitle: l10n.credentialsSubtitle,
          actions: [
            XpSelect<Project>(
              key: const Key('credentials.project'),
              value: widget.project,
              values: widget.projects,
              labelOf: (project) => project.fullName,
              onChanged: (project) => context.read<ShellCubit>().show(
                CredentialsDestination(project.id),
              ),
            ),
            XpButton(
              label: l10n.credentialsAdd,
              kind: XpButtonKind.primary,
              icon: PhosphorIconsRegular.plus,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed:
                  canCommand &&
                      form == null &&
                      flavorTargets(widget.project).isNotEmpty
                  ? _open
                  : null,
            ),
          ],
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (form != null) ...[
                CredentialForm(
                  key: ValueKey(form),
                  project: widget.project,
                  target: form.target,
                  kind: form.kind,
                  saving: state.save == CredentialSaveStatus.saving,
                  error: state.save == CredentialSaveStatus.failed
                      ? state.saveError
                      : null,
                  onCancel: _close,
                  onSubmit: (request) => context.read<CredentialsBloc>().add(
                    CredentialSaveRequested(request),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (state.error case final error?) ...[
                XpMessage(XpStatus.credentialExpired, error),
                const SizedBox(height: 12),
              ],
              _CredentialTable(
                project: widget.project,
                state: state,
                canCommand: canCommand,
                onReplace: (credential) => _open(
                  target: flavorTargets(widget.project).firstWhere(
                    (target) =>
                        target.app == credential.app &&
                        target.flavor == credential.flavor,
                    orElse: () => (
                      app: credential.app,
                      appName: credential.app,
                      flavor: credential.flavor,
                    ),
                  ),
                  kind: credential.kind,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CredentialTable extends StatelessWidget {
  const new({
    required this.project,
    required this.state,
    required this.canCommand,
    required this.onReplace,
  });

  final Project project;
  final CredentialsState state;
  final bool canCommand;
  final ValueChanged<Credential> onReplace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    if (state.loaded && state.credentials.isEmpty) {
      return XpPanel(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.credentialsEmpty,
          style: type.body.copyWith(color: colors.textSecondary),
        ),
      );
    }
    final bloc = context.read<CredentialsBloc>();
    final columns = [
      l10n.credentialsColumnFlavor,
      l10n.credentialsColumnKind,
      l10n.credentialsColumnAccount,
      l10n.credentialsColumnStatus,
      '',
    ];
    return XpPanel(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(0.8),
          1: FlexColumnWidth(1.4),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.4),
          4: IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final column in columns)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  child: XpSectionLabel(column),
                ),
            ],
          ),
          for (final credential in state.credentials)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              children: [
                _Cell(
                  XpCode(
                    credential.app == '.'
                        ? credential.flavor
                        : '${credential.app} · ${credential.flavor}',
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
                _Cell(_StatusCell(credential)),
                _Cell(
                  Row(
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
                      XpButton(
                        label: l10n.credentialsReplace,
                        size: XpButtonSize.small,
                        kind: XpButtonKind.tertiary,
                        onPressed: canCommand
                            ? () => onReplace(credential)
                            : null,
                      ),
                      const SizedBox(width: 6),
                      XpButton(
                        label: l10n.credentialsDelete,
                        size: XpButtonSize.small,
                        kind: XpButtonKind.tertiary,
                        onPressed: canCommand
                            ? () => bloc.add(
                                CredentialDeleteRequested(credential.id),
                              )
                            : null,
                      ),
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

class _StatusCell extends StatelessWidget {
  const new(this.credential);

  final Credential credential;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (status, label) = switch (credential.status) {
      CredentialStatus.verified => (
        XpStatus.credentialVerified,
        l10n.credentialVerified,
      ),
      CredentialStatus.rejected => (
        XpStatus.credentialExpired,
        l10n.credentialRejected,
      ),
      CredentialStatus.unverified || CredentialStatus.unreachable => (
        XpStatus.credentialExpiring,
        l10n.credentialUnchecked,
      ),
    };
    final detail = credential.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        XpStatusLabel(status, label),
        if (detail != null)
          Text(
            [detail, ?credential.fix].join(' '),
            style: context.xpType.caption.copyWith(
              color: context.xpColors.textSecondary,
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
