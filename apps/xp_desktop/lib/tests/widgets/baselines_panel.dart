import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The baselines of a project, one per app and branch: the runs that later
/// runs are compared with.
class BaselinesPanel extends StatelessWidget {
  const new({
    required this.baselines,
    required this.onShow,
    this.shownJobId,
    super.key,
  });

  final List<TestBaseline> baselines;

  /// The job of the run on screen.
  final String? shownJobId;

  /// Shows the run of a baseline's job.
  final ValueChanged<String> onShow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final code = type.code.copyWith(color: colors.textPrimary);
    final columns = [
      l10n.testsColumnApp,
      l10n.testsColumnBranch,
      l10n.testsStatPassed,
      l10n.testsStatFailed,
      l10n.testsStatSkipped,
      l10n.testsColumnWhen,
      '',
    ];
    Widget cell(Widget child) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 12, 8), child: child);
    return XpPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: XpSectionLabel(l10n.testsBaselinesTitle),
          ),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(1.4),
              1: FlexColumnWidth(1.4),
              2: FlexColumnWidth(),
              3: FlexColumnWidth(),
              4: FlexColumnWidth(),
              5: FlexColumnWidth(1.2),
              6: FixedColumnWidth(112),
            },
            children: [
              TableRow(
                children: [
                  for (final column in columns) cell(XpSectionLabel(column)),
                ],
              ),
              for (final baseline in baselines)
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.borderSubtle)),
                  ),
                  children: [
                    cell(Text(baseline.appPath, style: code)),
                    cell(Text(baseline.branch, style: code)),
                    cell(
                      Text(formatCount(baseline.counts.passed), style: code),
                    ),
                    cell(
                      Text(
                        formatCount(
                          baseline.counts.failed + baseline.counts.errored,
                        ),
                        style: code,
                      ),
                    ),
                    cell(
                      Text(formatCount(baseline.counts.skipped), style: code),
                    ),
                    cell(
                      Text(
                        formatDateTime(baseline.createdAt),
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    cell(
                      XpButton(
                        label: l10n.testsShowRun,
                        size: XpButtonSize.small,
                        kind: XpButtonKind.tertiary,
                        onPressed: baseline.jobId == shownJobId
                            ? null
                            : () => onShow(baseline.jobId),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
