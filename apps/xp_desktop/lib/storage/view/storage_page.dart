import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/storage/bloc/storage_bloc.dart';
import 'package:xp_desktop/storage/view/free_space_sheet.dart';
import 'package:xp_desktop/storage/widgets/retention_panel.dart';
import 'package:xp_desktop/storage/widgets/storage_labels.dart';
import 'package:xp_desktop/storage/widgets/storage_tables.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// What the engine keeps on its disk (PRODUCT §6.11): what each category
/// holds and gives back, the artifacts by app and flavor, retention, and
/// "Free up space…".
class StoragePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<StorageBloc>().state;
    final bloc = context.read<StorageBloc>();
    final report = state.report;
    final canCommand = context.canCommand;
    final busy = state.command != StorageCommand.none;
    final page = ShellPage(
      title: l10n.storageTitle,
      cached: state.cached,
      subtitle: report == null
          ? null
          : l10n.storageChecked(formatDateTime(report.generatedAt)),
      actions: [
        XpButton(
          label: l10n.storageRefresh,
          icon: PhosphorIconsRegular.arrowClockwise,
          tooltip: canCommand ? null : l10n.readOnlyHint,
          onPressed: canCommand && !busy
              ? () => bloc.add(const StorageSubscriptionRequested())
              : null,
        ),
        XpButton(
          label: l10n.storageFreeUp,
          icon: PhosphorIconsRegular.trash,
          kind: XpButtonKind.primary,
          busy: state.command == StorageCommand.freeing,
          tooltip: canCommand ? null : l10n.readOnlyHint,
          onPressed:
              canCommand &&
                  !busy &&
                  report != null &&
                  report.reclaimableBytes > 0
              ? () => _free(context, report)
              : null,
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.error case final error? when report == null)
            XpErrorState(
              error,
              onRetry: () => bloc.add(const StorageSubscriptionRequested()),
            )
          else if (state.error case final error?) ...[
            XpMessage.error(error),
            const SizedBox(height: 12),
          ],
          if (state.freed?.failures case final failures?)
            for (final failure in failures) ...[
              XpMessage(XpStatus.scanWarning, failure),
              const SizedBox(height: 6),
            ],
          if (report == null && state.error == null)
            const XpLoading(rows: 6)
          else if (report != null) ...[
            _Hero(report),
            const SizedBox(height: 24),
            CategoriesTable(report: report),
            const SizedBox(height: 16),
            if (report.flavors.isNotEmpty) ...[
              FlavorsTable(flavors: report.flavors),
              const SizedBox(height: 16),
            ],
            RetentionPanel(retention: report.retention),
          ],
        ],
      ),
    );
    return BlocListener<StorageBloc, StorageState>(
      listenWhen: (previous, current) =>
          current.freed != null && previous.freed != current.freed,
      listener: (context, state) =>
          context.read<ToastCubit>().show(freedText(l10n, state.freed!)),
      child: page,
    );
  }

  Future<void> _free(BuildContext context, StorageReport report) async {
    final bloc = context.read<StorageBloc>();
    final categories = await confirmFreeSpace(context, report);
    if (categories != null) bloc.add(StorageFreeRequested(categories));
  }
}

class _Hero extends StatelessWidget {
  const new(this.report);

  final StorageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.storageHero(
            formatSize(report.reclaimableBytes),
            formatSize(report.usedBytes),
          ),
          style: type.hero.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.storageHeroBody,
          style: type.body.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// What a "free up space" gave back: `Freed 1.2 GB · Builds 3, Logs 12`.
String freedText(AppLocalizations l10n, FreeSpaceResult result) {
  final parts = [
    for (final category in result.categories)
      if (category.items > 0)
        l10n.storageFreedPart(
          categoryName(category.category, l10n),
          category.items,
        ),
  ];
  return [
    l10n.storageFreed(formatSize(result.bytes)),
    if (parts.isNotEmpty) parts.join(', '),
  ].join(' · ');
}
