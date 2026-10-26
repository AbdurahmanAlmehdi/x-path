import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/command_labels.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The keys of ⌘1–⌘9: the projects in sidebar order.
const projectDigits = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// The menus of the macOS menu bar: XPath, Go, Project, Job, View and
/// Window, every shortcut of the keyboard guide in one of them.
List<PlatformMenuItem> appMenus(
  AppLocalizations l10n, {
  required List<String> projects,
  required void Function(int index) onProject,
}) {
  List<PlatformMenuItem> provided(List<PlatformProvidedMenuItemType> types) => [
    for (final type in types)
      if (PlatformProvidedMenuItem.hasMenu(type))
        PlatformProvidedMenuItem(type: type),
  ];
  PlatformMenuItem item(XpCommand command) => PlatformMenuItem(
    label: commandLabel(l10n, command),
    shortcut: command.activator,
    onSelected: () => runCommand(command),
  );
  PlatformMenu menu(String label, List<List<PlatformMenuItem>> groups) =>
      PlatformMenu(
        label: label,
        menus: [
          for (final group in groups)
            if (group.isNotEmpty) PlatformMenuItemGroup(members: group),
        ],
      );
  List<PlatformMenuItem> items(List<XpCommand> commands) => [
    for (final command in commands) item(command),
  ];
  return [
    menu('XPath', [
      provided(const [PlatformProvidedMenuItemType.about]),
      [item(XpCommand.settings)],
      provided(const [PlatformProvidedMenuItemType.servicesSubmenu]),
      provided(const [
        PlatformProvidedMenuItemType.hide,
        PlatformProvidedMenuItemType.hideOtherApplications,
        PlatformProvidedMenuItemType.showAllApplications,
      ]),
      provided(const [PlatformProvidedMenuItemType.quit]),
    ]),
    menu(l10n.menuGo, [
      items(const [XpCommand.palette, XpCommand.back, XpCommand.forward]),
      items(const [XpCommand.approvals]),
      [
        for (final (index, name) in projects.take(9).indexed)
          PlatformMenuItem(
            label: name,
            shortcut: SingleActivator(projectDigits[index], meta: true),
            onSelected: () => onProject(index),
          ),
      ],
    ]),
    menu(l10n.menuProject, [
      items(const [XpCommand.dispatch, XpCommand.console]),
    ]),
    menu(l10n.menuJob, [
      items(const [XpCommand.rerun, XpCommand.resume, XpCommand.cancel]),
      items(const [
        XpCommand.find,
        XpCommand.findNext,
        XpCommand.findPrevious,
        XpCommand.jumpToError,
      ]),
      items(const [XpCommand.followTail, XpCommand.timestamps, XpCommand.wrap]),
    ]),
    menu(l10n.menuView, [
      items(const [XpCommand.sidebar, XpCommand.compact, XpCommand.shortcuts]),
      provided(const [PlatformProvidedMenuItemType.toggleFullScreen]),
    ]),
    menu(l10n.menuWindow, [
      provided(const [
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
      ]),
      provided(const [PlatformProvidedMenuItemType.arrangeWindowsInFront]),
    ]),
  ];
}

/// The macOS menu bar around [child]; elsewhere (tests on other platforms,
/// a Linux build) only [child].
class AppMenuBar extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    final projects = context.watch<ProjectsBloc>().state.projects;
    return PlatformMenuBar(
      menus: appMenus(
        context.l10n,
        projects: [for (final project in projects) project.fullName],
        onProject: (index) => context.read<ShellCubit>().show(
          ProjectDestination(projects[index].id),
        ),
      ),
      child: child,
    );
  }
}
