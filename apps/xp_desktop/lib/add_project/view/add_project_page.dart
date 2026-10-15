import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/add_project/bloc/add_project_bloc.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/widgets/scan_summary.dart';
import 'package:xp_desktop/settings/bloc/github_token_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Add project by folder, then review what the scan found. The engine
/// needs its GitHub token to add a project; without one the form says so
/// and opens the GitHub section of the settings.
class AddProjectPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) =>
            AddProjectBloc(projects: context.read<ProjectsRepository>()),
      ),
      BlocProvider(
        create: (context) =>
            GitHubTokenBloc(settings: context.read<SettingsRepository>())
              ..add(const GitHubTokenRequested()),
      ),
    ],
    child: const AddProjectView(),
  );
}

class AddProjectView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<AddProjectBloc, AddProjectState>(
        listenWhen: (previous, current) =>
            current.status != previous.status &&
            (current.status == AddProjectStatus.discarded ||
                current.status == AddProjectStatus.failed),
        listener: (context, state) => state.status == AddProjectStatus.failed
            // A failure may be the token: ask again.
            ? context.read<GitHubTokenBloc>().add(const GitHubTokenRequested())
            : context.read<ShellCubit>().show(const HomeDestination()),
        builder: (context, state) => switch (state.status) {
          AddProjectStatus.review ||
          AddProjectStatus.scanning => _Review(state),
          _ => _Form(state),
        },
      );
}

class _Form extends StatefulWidget {
  const new(this.state);

  final AddProjectState state;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _folder = TextEditingController();

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final folder = await context.read<AppServices>().pickFolder();
    if (folder != null) _folder.text = folder;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final engine = context.watch<EngineConnectionBloc>().state.active;
    final local = engine?.isLocal ?? false;
    final adding = widget.state.status == AddProjectStatus.adding;
    final github = context.watch<GitHubTokenBloc>().state;
    final canCommand = context.canCommand;
    return ShellPage(
      title: l10n.addProjectTitle,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          XpPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.addProjectBody,
                  style: context.xpType.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (!local) ...[
                  const SizedBox(height: 8),
                  XpMessage(
                    XpStatus.scanInfo,
                    l10n.addProjectRemoteNote(engine?.name ?? ''),
                  ),
                ],
                if (github.needsToken) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: XpMessage(
                          XpStatus.credentialMissing,
                          github.status?.status == CredentialStatus.rejected
                              ? l10n.addProjectGitHubRejected
                              : l10n.addProjectNoGitHub,
                        ),
                      ),
                      const SizedBox(width: 12),
                      XpButton(
                        key: const Key('addProject.github'),
                        label: l10n.addProjectOpenGitHub,
                        icon: PhosphorIconsRegular.githubLogo,
                        kind: XpButtonKind.primary,
                        onPressed: () => context.read<ShellCubit>().show(
                          const SettingsDestination(github: true),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                XpTextField(
                  key: const Key('addProject.folder'),
                  label: l10n.addProjectFolder,
                  hint: l10n.addProjectFolderHint,
                  controller: _folder,
                  code: true,
                  trailing: local
                      ? XpButton(
                          label: l10n.addProjectChoose,
                          icon: PhosphorIconsRegular.folderOpen,
                          onPressed: _choose,
                        )
                      : null,
                ),
                if (widget.state.error case final error?) ...[
                  const SizedBox(height: 12),
                  XpMessage(XpStatus.scanError, l10n.addProjectFailed(error)),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ListenableBuilder(
                    listenable: _folder,
                    builder: (context, _) => XpButton(
                      label: adding
                          ? l10n.addProjectScanning
                          : l10n.addProjectAdd,
                      kind: XpButtonKind.primary,
                      busy: adding,
                      tooltip: canCommand ? null : l10n.readOnlyHint,
                      onPressed: _folder.text.trim().isEmpty || !canCommand
                          ? null
                          : () => context.read<AddProjectBloc>().add(
                              AddProjectSubmitted(_folder.text),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const new(this.state);

  final AddProjectState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final project = state.project!;
    final bloc = context.read<AddProjectBloc>();
    final canCommand = context.canCommand;
    return ShellPage(
      title: l10n.addProjectReviewTitle(project.fullName),
      actions: [
        XpButton(
          label: l10n.addProjectDiscard,
          kind: XpButtonKind.tertiary,
          onPressed: canCommand
              ? () => bloc.add(const AddProjectDiscarded())
              : null,
        ),
        XpButton(
          label: l10n.scanAgain,
          icon: PhosphorIconsRegular.arrowClockwise,
          busy: state.status == AddProjectStatus.scanning,
          onPressed: canCommand
              ? () => bloc.add(const AddProjectRescanned())
              : null,
        ),
        XpButton(
          label: l10n.addProjectKeep,
          kind: XpButtonKind.primary,
          onPressed: () =>
              context.read<ShellCubit>().show(ProjectDestination(project.id)),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l10n.addProjectReviewBody,
            style: context.xpType.body.copyWith(
              color: context.xpColors.textSecondary,
            ),
          ),
          if (state.error case final error?) ...[
            const SizedBox(height: 12),
            XpMessage(XpStatus.scanError, error),
          ],
          const SizedBox(height: 16),
          ScanSummary(project),
        ],
      ),
    );
  }
}
