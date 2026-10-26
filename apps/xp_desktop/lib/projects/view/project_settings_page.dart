import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/view/flavor_credentials_sheet.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/project_settings_bloc.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/widgets/project_host.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Project settings (U6d): the git host, the base branch, the gates, the
/// store ids of each flavor, and removing the project.
class ProjectSettingsPage extends StatelessWidget {
  const new(this.projectId, {super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectsBloc>().state.byId(projectId);
    if (project == null) {
      return ShellPage(
        title: context.l10n.sidebarProjectSettings,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, context.l10n.projectGone),
        ),
      );
    }
    return BlocProvider(
      key: ValueKey(projectId),
      create: (context) => ProjectSettingsBloc(
        projects: context.read<ProjectsRepository>(),
        approvals: context.read<ApprovalsRepository>(),
      )..add(ProjectSettingsStarted(projectId)),
      child: ProjectSettingsView(project: project),
    );
  }
}

class ProjectSettingsView extends StatefulWidget {
  const new({required this.project, super.key});

  final Project project;

  @override
  State<ProjectSettingsView> createState() => _ProjectSettingsViewState();
}

class _ProjectSettingsViewState extends State<ProjectSettingsView> {
  late final _branch = TextEditingController(
    text: widget.project.defaultBaseBranch,
  );

  @override
  void dispose() {
    _branch.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final bloc = context.read<ProjectSettingsBloc>();
    final confirmed = await confirmAction(
      context,
      title: l10n.projectRemoveTitle(widget.project.fullName),
      points: [l10n.projectRemovePoint],
      keep: l10n.projectRemoveKeep,
      confirm: l10n.projectRemoveConfirm,
    );
    if (confirmed) bloc.add(const ProjectRemoveRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final project = widget.project;
    final state = context.watch<ProjectSettingsBloc>().state;
    final bloc = context.read<ProjectSettingsBloc>();
    final canCommand = context.canCommand && !state.busy;
    Widget section(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XpSectionLabel(label),
          const SizedBox(height: 8),
          XpPanel(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
    return MultiBlocListener(
      listeners: [
        BlocListener<ProjectSettingsBloc, ProjectSettingsState>(
          listenWhen: (previous, current) => current.saved != previous.saved,
          listener: (context, _) => context.read<ToastCubit>().show(
            l10n.projectBaseBranchSaved(_branch.text.trim()),
          ),
        ),
        BlocListener<ProjectSettingsBloc, ProjectSettingsState>(
          listenWhen: (previous, current) => current.removed,
          listener: (context, _) =>
              context.read<ShellCubit>().show(const HomeDestination()),
        ),
      ],
      child: ShellPage(
        title: l10n.sidebarProjectSettings,
        subtitle: project.fullName,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (state.error case final error?) ...[
              XpMessage.error(error),
              const SizedBox(height: 12),
            ],
            section(
              l10n.projectGitHost,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.hostLabel(l10n),
                    style: type.body.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  XpCode(project.remote, color: colors.textSecondary),
                ],
              ),
            ),
            section(
              l10n.projectBaseBranch,
              Row(
                children: [
                  Expanded(
                    child: XpTextField(
                      key: const Key('project.baseBranch'),
                      controller: _branch,
                      code: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  XpButton(
                    label: l10n.projectBaseBranchSave,
                    busy: state.command == ProjectSettingsCommand.saving,
                    onPressed: canCommand
                        ? () => bloc.add(ProjectBaseBranchSaved(_branch.text))
                        : null,
                  ),
                ],
              ),
            ),
            section(
              l10n.projectGates,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.projectGatesBody,
                    style: type.body.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  if (state.gates case final gates?)
                    for (final MapEntry(key: action, value: on)
                        in gates.entries)
                      XpCheckbox(
                        label: l10n.gateAction(action),
                        value: on,
                        onChanged: canCommand
                            ? (on) =>
                                  bloc.add(ProjectGateChanged(action, on: on))
                            : null,
                      )
                  else
                    const XpLoading(),
                ],
              ),
            ),
            section(
              l10n.projectStoreIds,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final app in project.profile.apps)
                    for (final flavor in app.flavors)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                if (project.profile.apps.length > 1) app.name,
                                flavor.name,
                              ].join(' · '),
                              style: type.body.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          XpButton(
                            label: l10n.setupSetIds,
                            size: XpButtonSize.small,
                            onPressed: () => unawaited(
                              showFlavorCredentialsSheet(
                                context,
                                project: project,
                                target: (
                                  app: app.path,
                                  appName: app.name,
                                  flavor: flavor.name,
                                ),
                                focusStoreIds: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                ],
              ),
            ),
            section(
              l10n.projectRemove,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.projectRemoveBody,
                      style: type.body.copyWith(color: colors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  XpButton(
                    key: const Key('project.remove'),
                    label: l10n.projectRemoveButton,
                    icon: PhosphorIconsRegular.trash,
                    kind: XpButtonKind.destructive,
                    busy: state.command == ProjectSettingsCommand.removing,
                    onPressed: canCommand ? () => unawaited(_remove()) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
