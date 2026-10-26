import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// What the menu bar, the shortcut sheet and the palette call [command].
String commandLabel(AppLocalizations l10n, XpCommand command) =>
    switch (command) {
      XpCommand.palette => l10n.commandPalette,
      XpCommand.dispatch => l10n.commandDispatch,
      XpCommand.rerun => l10n.commandRerun,
      XpCommand.resume => l10n.commandResume,
      XpCommand.cancel => l10n.commandCancel,
      XpCommand.approvals => l10n.commandApprovals,
      XpCommand.back => l10n.commandBack,
      XpCommand.forward => l10n.commandForward,
      XpCommand.sidebar => l10n.commandSidebar,
      XpCommand.console => l10n.commandConsole,
      XpCommand.find => l10n.commandFind,
      XpCommand.findNext => l10n.commandFindNext,
      XpCommand.findPrevious => l10n.commandFindPrevious,
      XpCommand.jumpToError => l10n.commandJumpToError,
      XpCommand.followTail => l10n.commandFollowTail,
      XpCommand.timestamps => l10n.commandTimestamps,
      XpCommand.wrap => l10n.commandWrap,
      XpCommand.compact => l10n.commandCompact,
      XpCommand.shortcuts => l10n.commandShortcuts,
      XpCommand.settings => l10n.commandSettings,
    };

/// What the palette and the menu bar call the page [destination].
String pageLabel(AppLocalizations l10n, ShellDestination destination) =>
    switch (destination) {
      ReleasesDestination() => l10n.releasesTitle,
      RunsDestination() => l10n.runsTitle,
      TestsDestination() => l10n.testsTitle,
      WorkflowsDestination() => l10n.workflowsTitle,
      ApprovalsDestination() => l10n.approvalsTitle,
      RunnersDestination() => l10n.runnersTitle,
      CredentialsDestination() => l10n.credentialsTitle,
      StorageDestination() => l10n.storageTitle,
      EnginesDestination() => l10n.enginesTitle,
      SettingsDestination() => l10n.settingsTitle,
      ProjectSettingsDestination() => l10n.sidebarProjectSettings,
      AddProjectDestination() => l10n.sidebarAddProject,
      OnboardingDestination() => l10n.onboardingTitle,
      HomeDestination() ||
      ProjectDestination() ||
      JobDestination() => l10n.sidebarOverview,
    };
