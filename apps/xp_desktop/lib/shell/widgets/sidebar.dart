import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/engine_switcher.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The sidebar of `Main.dc.html`: the brand, the engine switcher, the
/// projects of the engine, the engine-wide rows and "Add project…".
class Sidebar extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final destination = context.watch<ShellCubit>().state;
    final projects = context.watch<ProjectsBloc>().state;
    final selectedProject = switch (destination) {
      ProjectDestination(:final projectId) => projectId,
      HomeDestination() when projects.projects.isNotEmpty =>
        projects.projects.first.id,
      _ => null,
    };
    void show(ShellDestination destination) =>
        context.read<ShellCubit>().show(destination);

    return Container(
      width: context.xpSizes.sidebarWidth,
      color: colors.surfaceSidebar,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          const SizedBox(height: 10),
          const EngineSwitcher(),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                _Caption(l10n.sidebarProjects),
                if (projects.projects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      projects.loaded ? l10n.sidebarNoProjects : '',
                      style: context.xpType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                for (final project in projects.projects)
                  _ProjectRow(
                    project: project,
                    selected: project.id == selectedProject,
                    onTap: () => show(ProjectDestination(project.id)),
                  ),
                const SizedBox(height: 18),
                _Caption(l10n.sidebarEngine),
                SidebarRow(
                  icon: PhosphorIconsRegular.key,
                  selectedIcon: PhosphorIconsFill.key,
                  label: l10n.sidebarCredentials,
                  selected: destination is CredentialsDestination,
                  onTap: () => show(const CredentialsDestination()),
                ),
                SidebarRow(
                  icon: PhosphorIconsRegular.hardDrives,
                  selectedIcon: PhosphorIconsFill.hardDrives,
                  label: l10n.sidebarEngines,
                  selected:
                      destination is EnginesDestination ||
                      destination is OnboardingDestination,
                  onTap: () => show(const EnginesDestination()),
                ),
              ],
            ),
          ),
          SidebarRow(
            icon: PhosphorIconsRegular.plus,
            selectedIcon: PhosphorIconsFill.plus,
            label: l10n.sidebarAddProject,
            selected: destination is AddProjectDestination,
            onTap: () => show(const AddProjectDestination()),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        Image.asset(
          'assets/brand/xpath-sidebar.png',
          height: 15,
          color: context.xpColors.textPrimary,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.appTitle,
          style: context.xpType.titleSm.copyWith(
            color: context.xpColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

class _Caption extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
    child: XpSectionLabel(text),
  );
}

/// A row of the sidebar: `size.row.sidebar` tall; selected rows sit on
/// `surface.selected` with an inset strong border and a filled icon.
class SidebarRow extends StatefulWidget {
  const new({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<SidebarRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return _Hoverable(
      selected: widget.selected,
      hovered: _hovered,
      onHover: (value) => setState(() => _hovered = value),
      onTap: widget.onTap,
      label: widget.label,
      child: SizedBox(
        height: context.xpSizes.rowSidebar,
        child: Row(
          children: [
            Icon(
              widget.selected ? widget.selectedIcon : widget.icon,
              size: context.xpSizes.iconMd,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style:
                    (widget.selected
                            ? context.xpType.bodyStrong
                            : context.xpType.body)
                        .copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectRow extends StatefulWidget {
  const new({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final project = widget.project;
    final errors = project.findings
        .where((finding) => finding.severity == FindingSeverity.error)
        .length;
    final warnings = project.findings
        .where((finding) => finding.severity == FindingSeverity.warning)
        .length;
    final apps = l10n.projectApps(project.profile.apps.length);
    final Widget meta = errors > 0
        ? XpStatusLabel(
            XpStatus.scanError,
            '$apps · ${l10n.projectErrors(errors)}',
          )
        : warnings > 0
        ? XpStatusLabel(
            XpStatus.scanWarning,
            '$apps · ${l10n.projectWarnings(warnings)}',
          )
        : Text(apps, style: type.caption.copyWith(color: colors.textSecondary));
    return _Hoverable(
      selected: widget.selected,
      hovered: _hovered,
      onHover: (value) => setState(() => _hovered = value),
      onTap: widget.onTap,
      label: project.fullName,
      child: SizedBox(
        height: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.fullName.split('/').last,
              overflow: TextOverflow.ellipsis,
              style: (widget.selected ? type.titleSm : type.body).copyWith(
                color: colors.textPrimary,
                height: 1.3,
              ),
            ),
            meta,
          ],
        ),
      ),
    );
  }
}

class _Hoverable extends StatelessWidget {
  const new({
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onTap,
    required this.label,
    required this.child,
  });

  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: context.xpMotion.durationFast,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? colors.surfaceSelected
                  : hovered
                  ? colors.surfaceHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(context.xpRadii.md),
              border: Border.all(
                color: selected ? colors.borderStrong : Colors.transparent,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
