import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/add_project/view/add_project_page.dart';
import 'package:xp_desktop/credentials/view/credentials_page.dart';
import 'package:xp_desktop/engines/view/engines_page.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/onboarding/view/onboarding_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/view/project_page.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/shell/widgets/sidebar.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The window: the sidebar and the content area of the destination.
class AppShell extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: context.xpColors.surfaceWindow,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Sidebar(),
        const XpHairline(vertical: true),
        Expanded(
          child: BlocBuilder<ShellCubit, ShellDestination>(
            builder: (context, destination) => switch (destination) {
              HomeDestination() => const _Home(),
              ProjectDestination(:final projectId) => ProjectPage(projectId),
              AddProjectDestination() => const AddProjectPage(),
              CredentialsDestination(:final projectId) => CredentialsPage(
                projectId: projectId,
              ),
              EnginesDestination() => const EnginesPage(),
              OnboardingDestination() => const OnboardingPage(),
            },
          ),
        ),
      ],
    ),
  );
}

class _Home extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectsBloc>().state;
    if (!state.loaded) {
      return ShellPage(title: context.l10n.appTitle, child: const SizedBox());
    }
    if (state.projects.isEmpty) return const NoProjectsPage();
    return ProjectPage(state.projects.first.id);
  }
}
