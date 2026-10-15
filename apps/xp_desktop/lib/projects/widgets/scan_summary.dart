import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// What a scan found: one panel per app with a ledger of its flavors, then
/// the findings, worst first, each with its fix.
class ScanSummary extends StatelessWidget {
  const new(this.project, {super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final findings = [...project.findings]
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (project.profile.apps.isEmpty)
          XpMessage(XpStatus.scanWarning, l10n.scanNoApps),
        for (final app in project.profile.apps) ...[
          _AppPanel(app),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 8),
        XpSectionLabel(l10n.scanFindings),
        const SizedBox(height: 8),
        XpPanel(
          child: findings.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.scanNoFindings,
                    style: context.xpType.body.copyWith(
                      color: context.xpColors.textSecondary,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final (index, finding) in findings.indexed) ...[
                      if (index > 0) const XpHairline(),
                      _FindingRow(finding),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AppPanel extends StatelessWidget {
  const new(this.app);

  final AppProfile app;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final secondary = type.code.copyWith(color: colors.textSecondary);
    final columns = [
      l10n.scanColumnFlavor,
      l10n.scanColumnIos,
      l10n.scanColumnAndroid,
      l10n.scanColumnShorebird,
    ];
    return XpPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  app.name,
                  style: type.title.copyWith(color: colors.textPrimary),
                ),
                Text(
                  l10n.scanAppMeta(
                    app.path,
                    app.flutterVersion ?? l10n.scanUnpinned,
                    app.storeCountry.toUpperCase(),
                  ),
                  style: secondary,
                ),
                if (app.hasIos)
                  const _Chip(PhosphorIconsRegular.appleLogo, 'iOS'),
                if (app.hasAndroid)
                  const _Chip(PhosphorIconsRegular.androidLogo, 'Android'),
              ],
            ),
          ),
          const XpHairline(),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FlexColumnWidth(1.6),
              2: FlexColumnWidth(1.6),
              3: FixedColumnWidth(110),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  for (final column in columns)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      child: XpSectionLabel(column),
                    ),
                ],
              ),
              for (final flavor in app.flavors)
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.borderSubtle)),
                  ),
                  children: [
                    _Cell(
                      Row(
                        children: [
                          Text(
                            flavor.name,
                            style: type.titleSm.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          if (flavor.prod) ...[
                            const SizedBox(width: 6),
                            XpBadge(XpStatus.releaseLive, l10n.scanProd),
                          ],
                        ],
                      ),
                    ),
                    _Cell(_Id(flavor.iosBundleId)),
                    _Cell(_Id(flavor.androidAppId)),
                    _Cell(
                      Text(
                        flavor.shorebird
                            ? l10n.scanShorebirdOn
                            : l10n.scanShorebirdOff,
                        style: type.body.copyWith(color: colors.textSecondary),
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

class _Cell extends StatelessWidget {
  const new(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 12, 8), child: child);
}

class _Id extends StatelessWidget {
  const new(this.value);

  final String? value;

  @override
  Widget build(BuildContext context) => value == null
      ? Text(
          '—',
          style: context.xpType.code.copyWith(
            color: context.xpColors.textTertiary,
          ),
        )
      : XpCode(value!);
}

class _Chip extends StatelessWidget {
  const new(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(context.xpRadii.sm),
      border: Border.all(color: context.xpColors.borderDefault),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: context.xpSizes.iconXs,
          color: context.xpColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.xpType.caption.copyWith(
            color: context.xpColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _FindingRow extends StatelessWidget {
  const new(this.finding);

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final (status, label) = switch (finding.severity) {
      FindingSeverity.error => (XpStatus.scanError, l10n.scanError),
      FindingSeverity.warning => (XpStatus.scanWarning, l10n.scanWarning),
      FindingSeverity.info => (XpStatus.scanInfo, l10n.scanInfo),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: XpStatusLabel(status, label)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.message,
                  style: type.body.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.scanFix(finding.fix),
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
                if (finding.path case final path?) ...[
                  const SizedBox(height: 2),
                  XpCode(path, color: colors.textSecondary),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
