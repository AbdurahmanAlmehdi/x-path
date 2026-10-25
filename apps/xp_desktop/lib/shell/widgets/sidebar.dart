import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/runners/bloc/runners_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/engine_switcher.dart';
import 'package:xp_desktop/storage/bloc/storage_bloc.dart';
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
    final pending = context.watch<PendingApprovalsBloc>().state.approvals;
    final busyRunners = context.select<RunnersBloc, int>(
      (bloc) => bloc.state.busy,
    );
    final reclaimable = context.select<StorageBloc, int?>(
      (bloc) => bloc.state.report?.reclaimableBytes,
    );
    final selectedProject = switch (destination) {
      ProjectDestination(:final projectId) => projectId,
      ReleasesDestination(:final projectId) => projectId,
      TestsDestination(:final projectId) => projectId,
      WorkflowsDestination(:final projectId) => projectId,
      RunsDestination(:final projectId) => projectId,
      JobDestination(:final projectId) => projectId,
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
                for (final project in projects.projects) ...[
                  _ProjectRow(
                    project: project,
                    selected: project.id == selectedProject,
                    needsYou: pending
                        .where((approval) => approval.projectId == project.id)
                        .length,
                    onTap: () => show(ProjectDestination(project.id)),
                  ),
                  if (project.id == selectedProject) ...[
                    SidebarRow(
                      icon: PhosphorIconsRegular.treeStructure,
                      selectedIcon: PhosphorIconsFill.treeStructure,
                      label: l10n.sidebarOverview,
                      indent: 12,
                      selected:
                          destination is ProjectDestination ||
                          destination is HomeDestination,
                      onTap: () => show(ProjectDestination(project.id)),
                    ),
                    SidebarRow(
                      icon: PhosphorIconsRegular.package,
                      selectedIcon: PhosphorIconsFill.package,
                      label: l10n.sidebarReleases,
                      indent: 12,
                      selected: destination is ReleasesDestination,
                      onTap: () => show(ReleasesDestination(project.id)),
                    ),
                    SidebarRow(
                      icon: PhosphorIconsRegular.playCircle,
                      selectedIcon: PhosphorIconsFill.playCircle,
                      label: l10n.sidebarRuns,
                      indent: 12,
                      selected:
                          destination is RunsDestination ||
                          destination is JobDestination,
                      onTap: () => show(RunsDestination(project.id)),
                    ),
                    SidebarRow(
                      icon: PhosphorIconsRegular.testTube,
                      selectedIcon: PhosphorIconsFill.testTube,
                      label: l10n.sidebarTests,
                      indent: 12,
                      selected: destination is TestsDestination,
                      onTap: () => show(TestsDestination(project.id)),
                    ),
                    SidebarRow(
                      icon: PhosphorIconsRegular.flowArrow,
                      selectedIcon: PhosphorIconsFill.flowArrow,
                      label: l10n.sidebarWorkflows,
                      indent: 12,
                      selected: destination is WorkflowsDestination,
                      onTap: () => show(WorkflowsDestination(project.id)),
                    ),
                  ],
                ],
                const SizedBox(height: 18),
                _Caption(l10n.sidebarEngine),
                SidebarRow(
                  icon: PhosphorIconsRegular.handPalm,
                  selectedIcon: PhosphorIconsFill.handPalm,
                  label: l10n.sidebarApprovals,
                  selected: destination is ApprovalsDestination,
                  count: pending.length,
                  onTap: () => show(const ApprovalsDestination()),
                ),
                SidebarRow(
                  icon: PhosphorIconsRegular.hardDrives,
                  selectedIcon: PhosphorIconsFill.hardDrives,
                  label: l10n.sidebarRunners,
                  selected: destination is RunnersDestination,
                  meta: busyRunners > 0
                      ? l10n.sidebarRunnersBusy(busyRunners)
                      : null,
                  onTap: () => show(const RunnersDestination()),
                ),
                SidebarRow(
                  icon: PhosphorIconsRegular.key,
                  selectedIcon: PhosphorIconsFill.key,
                  label: l10n.sidebarCredentials,
                  selected: destination is CredentialsDestination,
                  onTap: () => show(const CredentialsDestination()),
                ),
                SidebarRow(
                  icon: PhosphorIconsRegular.database,
                  selectedIcon: PhosphorIconsFill.database,
                  label: l10n.sidebarStorage,
                  selected: destination is StorageDestination,
                  meta: reclaimable == null || reclaimable == 0
                      ? null
                      : l10n.sidebarStorageFreeable(formatSize(reclaimable)),
                  onTap: () => show(const StorageDestination()),
                ),
                SidebarRow(
                  icon: PhosphorIconsRegular.laptop,
                  selectedIcon: PhosphorIconsFill.laptop,
                  label: l10n.sidebarEngines,
                  selected:
                      destination is EnginesDestination ||
                      destination is OnboardingDestination,
                  onTap: () => show(const EnginesDestination()),
                ),
                SidebarRow(
                  icon: PhosphorIconsRegular.gearSix,
                  selectedIcon: PhosphorIconsFill.gearSix,
                  label: l10n.sidebarSettings,
                  selected: destination is SettingsDestination,
                  onTap: () => show(const SettingsDestination()),
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
    this.indent = 0,
    this.count = 0,
    this.meta,
    super.key,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// How far the row sits in, for the rows of the selected project.
  final double indent;

  /// What waits for the owner here: the needs-you count badge, the only
  /// warning fill besides the needs-you bar (Colour guide).
  final int count;

  /// A short fact at the trailing end, for example `2 busy`.
  final String? meta;

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
            SizedBox(width: widget.indent),
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
            if (widget.meta case final meta?)
              Text(
                meta,
                style: context.xpType.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            if (widget.count > 0) _CountBadge(widget.count),
          ],
        ),
      ),
    );
  }
}

/// The needs-you count: `color.warning.default` with its on-colour.
class _CountBadge extends StatelessWidget {
  const new(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: context.xpColors.warningDefault,
      borderRadius: BorderRadius.circular(context.xpRadii.full),
    ),
    child: Text(
      '$count',
      style: context.xpType.label.copyWith(
        color: context.xpColors.warningOnWarning,
      ),
    ),
  );
}

class _ProjectRow extends StatefulWidget {
  const new({
    required this.project,
    required this.selected,
    required this.onTap,
    this.needsYou = 0,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  /// How many approvals of the project wait.
  final int needsYou;

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
    final Widget meta = widget.needsYou > 0
        ? XpStatusLabel(
            XpStatus.approvalPending,
            '$apps · ${l10n.overviewNeedsYou(widget.needsYou)}',
          )
        : errors > 0
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
