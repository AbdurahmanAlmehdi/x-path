import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/storage/widgets/storage_labels.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Asks which categories to free, from what [report] says each would give
/// back. The categories picked, or `null` when the owner keeps everything.
/// Return does nothing; Escape keeps everything.
Future<List<StorageCategory>?> confirmFreeSpace(
  BuildContext context,
  StorageReport report,
) => showDialog<List<StorageCategory>>(
  context: context,
  barrierColor: context.xpColors.scrimDefault,
  builder: (_) => FreeSpaceSheet(report: report),
);

class FreeSpaceSheet extends StatefulWidget {
  const new({required this.report, super.key});

  final StorageReport report;

  @override
  State<FreeSpaceSheet> createState() => _FreeSpaceSheetState();
}

class _FreeSpaceSheetState extends State<FreeSpaceSheet> {
  late final Set<StorageCategory> _picked = {
    for (final usage in _offered) usage.category,
  };

  List<CategoryUsage> get _offered => [
    for (final usage in widget.report.categories)
      if (usage.reclaimableBytes > 0) usage,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final offered = _offered;
    final bytes = offered
        .where((usage) => _picked.contains(usage.category))
        .fold(0, (sum, usage) => sum + usage.reclaimableBytes);
    void close(List<StorageCategory>? picked) =>
        Navigator.of(context).pop(picked);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => close(null),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter):
              DoNothingAndStopPropagationIntent(),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: colors.surfaceOverlay,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.xpRadii.lg),
              side: BorderSide(color: colors.borderStrong),
            ),
            child: SizedBox(
              width: 520,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.freeSpaceTitle,
                      style: type.headline.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.freeSpaceBody,
                      style: type.body.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    for (final usage in offered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            XpChip(
                              label: categoryName(usage.category, l10n),
                              selected: _picked.contains(usage.category),
                              onChanged: (on) => setState(
                                () => on
                                    ? _picked.add(usage.category)
                                    : _picked.remove(usage.category),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                categoryRule(
                                  usage.category,
                                  widget.report.retention,
                                  l10n,
                                ),
                                overflow: TextOverflow.ellipsis,
                                style: type.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              formatSize(usage.reclaimableBytes),
                              style: type.code.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        XpButton(
                          label: l10n.freeSpaceKeep,
                          size: XpButtonSize.large,
                          onPressed: () => close(null),
                        ),
                        const SizedBox(width: 8),
                        XpButton(
                          label: l10n.freeSpaceConfirm(formatSize(bytes)),
                          kind: XpButtonKind.destructive,
                          size: XpButtonSize.large,
                          onPressed: _picked.isEmpty
                              ? null
                              : () => close([
                                  for (final usage in offered)
                                    if (_picked.contains(usage.category))
                                      usage.category,
                                ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
