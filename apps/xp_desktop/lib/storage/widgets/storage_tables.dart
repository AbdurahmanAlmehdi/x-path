import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/storage/widgets/storage_labels.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// What each category holds, what housekeeping would give back of it and
/// by which rule.
class CategoriesTable extends StatelessWidget {
  const new({required this.report, super.key});

  final StorageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final code = type.code.copyWith(color: colors.textPrimary);
    return _TablePanel(
      title: l10n.storageCategoriesTitle,
      columns: [
        l10n.storageColumnCategory,
        l10n.storageColumnItems,
        l10n.storageColumnUsed,
        l10n.storageColumnReclaimable,
        '',
      ],
      widths: const {
        0: FlexColumnWidth(3),
        1: FixedColumnWidth(80),
        2: FixedColumnWidth(110),
        3: FixedColumnWidth(120),
        4: FlexColumnWidth(1.2),
      },
      rows: [
        for (final usage in report.categories)
          [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoryName(usage.category, l10n),
                  style: type.titleSm.copyWith(color: colors.textPrimary),
                ),
                Text(
                  categoryRule(usage.category, report.retention, l10n),
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            Text(formatCount(usage.items), style: code),
            Text(formatSize(usage.usedBytes), style: code),
            Text(formatSize(usage.reclaimableBytes), style: code),
            _Meter(
              usage.usedBytes == 0
                  ? 0
                  : usage.reclaimableBytes / usage.usedBytes,
            ),
          ],
      ],
    );
  }
}

/// The artifacts by app and flavor.
class FlavorsTable extends StatelessWidget {
  const new({required this.flavors, super.key});

  final List<FlavorUsage> flavors;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final code = type.code.copyWith(color: colors.textPrimary);
    final projects = context.watch<ProjectsBloc>().state;
    return _TablePanel(
      title: l10n.storageFlavorsTitle,
      columns: [
        l10n.storageColumnProject,
        l10n.storageColumnApp,
        l10n.storageColumnFlavor,
        l10n.storageColumnBuilds,
        l10n.storageColumnUsed,
        l10n.storageColumnReclaimable,
      ],
      widths: const {
        0: FlexColumnWidth(1.6),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(170),
        4: FixedColumnWidth(110),
        5: FixedColumnWidth(120),
      },
      rows: [
        for (final flavor in flavors)
          [
            Text(
              projects.byId(flavor.projectId)?.fullName.split('/').last ??
                  flavor.projectId,
              overflow: TextOverflow.ellipsis,
              style: type.body.copyWith(color: colors.textPrimary),
            ),
            Text(flavor.app, overflow: TextOverflow.ellipsis, style: code),
            Text(
              flavor.flavor.isEmpty ? '—' : flavor.flavor,
              style: type.body.copyWith(color: colors.textPrimary),
            ),
            Text(
              l10n.storageBuilds(flavor.builds, flavor.artifacts),
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            Text(formatSize(flavor.usedBytes), style: code),
            Text(formatSize(flavor.reclaimableBytes), style: code),
          ],
      ],
    );
  }
}

class _TablePanel extends StatelessWidget {
  const new({
    required this.title,
    required this.columns,
    required this.widths,
    required this.rows,
  });

  final String title;
  final List<String> columns;
  final Map<int, TableColumnWidth> widths;
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 12, 8), child: child);
    return XpPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              title,
              style: context.xpType.title.copyWith(
                color: context.xpColors.textPrimary,
              ),
            ),
          ),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: widths,
            children: [
              TableRow(
                children: [
                  for (final column in columns) cell(XpSectionLabel(column)),
                ],
              ),
              for (final row in rows)
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: context.xpColors.borderSubtle),
                    ),
                  ),
                  children: [for (final child in row) cell(child)],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How much of a category housekeeping would give back: a fill on a sunken
/// track (`radius.full`, fill `radius.xs`).
class _Meter extends StatelessWidget {
  const new(this.share);

  final double share;

  @override
  Widget build(BuildContext context) => Container(
    height: 6,
    decoration: BoxDecoration(
      color: context.xpColors.surfaceSunken,
      borderRadius: BorderRadius.circular(context.xpRadii.full),
    ),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: share.clamp(0, 1),
      child: Container(
        decoration: BoxDecoration(
          color: context.xpColors.positiveDefault,
          borderRadius: BorderRadius.circular(context.xpRadii.xs),
        ),
      ),
    ),
  );
}
