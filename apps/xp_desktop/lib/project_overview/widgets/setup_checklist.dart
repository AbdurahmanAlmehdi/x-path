import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/credentials/view/flavor_credentials_sheet.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/bloc/setup_checklist_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The way from a new engine to a first green build (U5a), on NoProjects and
/// the overview of [project]: each step done or with the button that does
/// it. It hides once every step is done or the project has a release.
class SetupChecklist extends StatelessWidget {
  const new({this.project, super.key});

  /// The project, or `null` on an engine with none yet.
  final Project? project;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(project),
    create: (context) => SetupChecklistBloc(
      settings: context.read<SettingsRepository>(),
      projects: context.read<ProjectsRepository>(),
      jobs: context.read<JobsRepository>(),
      releases: context.read<ReleasesRepository>(),
      workflows: context.read<WorkflowsRepository>(),
    )..add(SetupChecklistStarted(project)),
    child: const SetupChecklistView(),
  );
}

class SetupChecklistView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<SetupChecklistBloc>().state;
    if (!state.visible) return const SizedBox.shrink();
    final steps = state.steps;
    final next = steps.firstWhere((step) => !step.done);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: XpPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.setupTitle,
                      style: context.xpType.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    l10n.setupProgress(state.doneCount, steps.length),
                    style: context.xpType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            for (final step in steps) ...[
              const XpHairline(),
              _StepRow(step, current: identical(step, next)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const new(this.step, {required this.current});

  final SetupStep step;

  /// Whether it is the first step not done, whose button leads.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final body = step.done ? null : _body(l10n);
    return Padding(
      key: Key('setup.${step.kind.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              step.done
                  ? PhosphorIconsFill.checkCircle
                  : PhosphorIconsRegular.circle,
              size: context.xpSizes.iconSm,
              color: step.done
                  ? colors.onContainer(XpStatusPair.positive)
                  : colors.textTertiary,
              semanticLabel: step.done ? l10n.stepDone : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(l10n),
                  style: (current ? type.bodyStrong : type.body).copyWith(
                    color: step.done
                        ? colors.textSecondary
                        : colors.textPrimary,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (!step.done) ...[
            const SizedBox(width: 12),
            Wrap(spacing: 8, children: _actions(context)),
          ],
        ],
      ),
    );
  }

  String _title(AppLocalizations l10n) => switch (step.kind) {
    SetupStepKind.engine => l10n.setupEngine,
    SetupStepKind.gitHub => l10n.setupGitHub,
    SetupStepKind.project => l10n.setupProject,
    SetupStepKind.credentials => l10n.setupCredentials,
    SetupStepKind.storeIds => l10n.setupStoreIds,
    SetupStepKind.runners => l10n.setupRunners,
    SetupStepKind.firstBuild => l10n.setupFirstBuild,
  };

  String? _body(AppLocalizations l10n) => switch (step.kind) {
    SetupStepKind.engine => null,
    SetupStepKind.gitHub => l10n.setupGitHubBody,
    SetupStepKind.project => l10n.setupProjectBody,
    SetupStepKind.credentials => switch (step.target) {
      final target? => l10n.setupCredentialsBody(target.flavor),
      null => null,
    },
    SetupStepKind.storeIds => switch (step.target) {
      final target? => l10n.setupStoreIdsBody(target.flavor),
      null => null,
    },
    SetupStepKind.runners => step.reasons?.join(' '),
    SetupStepKind.firstBuild => l10n.setupFirstBuildBody,
  };

  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    final state = context.read<SetupChecklistBloc>().state;
    final project = state.project;
    final shell = context.read<ShellCubit>();
    final kind = current ? XpButtonKind.primary : XpButtonKind.secondary;
    XpButton button(String label, VoidCallback? onPressed) => XpButton(
      label: label,
      kind: kind,
      size: XpButtonSize.small,
      onPressed: onPressed,
    );
    final target = step.target;
    return switch (step.kind) {
      SetupStepKind.engine => const [],
      SetupStepKind.gitHub => [
        button(
          l10n.setupConnect,
          () => shell.show(const SettingsDestination(github: true)),
        ),
      ],
      SetupStepKind.project => [
        button(l10n.setupAdd, () => shell.show(const AddProjectDestination())),
      ],
      SetupStepKind.credentials ||
      SetupStepKind.storeIds when project != null && target != null => [
        button(
          step.kind == SetupStepKind.credentials
              ? l10n.setupAssign
              : l10n.setupSetIds,
          () => unawaited(
            showFlavorCredentialsSheet(
              context,
              project: project,
              target: target,
              focusStoreIds: step.kind == SetupStepKind.storeIds,
            ),
          ),
        ),
      ],
      SetupStepKind.credentials || SetupStepKind.storeIds => const [],
      SetupStepKind.runners => [
        button(
          l10n.setupRunnersOpen,
          () => shell.show(const RunnersDestination()),
        ),
        XpButton(
          label: l10n.setupRunnersGuide,
          icon: PhosphorIconsRegular.arrowSquareOut,
          kind: XpButtonKind.tertiary,
          size: XpButtonSize.small,
          onPressed: () => unawaited(
            context.read<AppServices>().openUrl(guideUri('runners.md')),
          ),
        ),
      ],
      SetupStepKind.firstBuild when project != null => [
        if (_smokeOf(state, project) case final smoke?)
          button(
            l10n.setupTrySmoke,
            context.canCommand
                ? () => unawaited(
                    dispatchFor(context, project, workflowId: smoke),
                  )
                : null,
          ),
        XpButton(
          label: l10n.setupDispatch,
          kind: _smokeOf(state, project) == null
              ? kind
              : XpButtonKind.secondary,
          size: XpButtonSize.small,
          onPressed: context.canCommand
              ? () => unawaited(dispatchFor(context, project))
              : null,
        ),
      ],
      SetupStepKind.firstBuild => const [],
    };
  }

  /// The smoke build to offer: it builds Android, so only for a project
  /// with an Android app.
  static String? _smokeOf(SetupChecklistState state, Project project) =>
      project.profile.apps.any((app) => app.hasAndroid)
      ? state.smokeWorkflowId
      : null;
}
