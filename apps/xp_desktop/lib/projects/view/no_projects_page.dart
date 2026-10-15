import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The content area when the engine has no project yet.
class NoProjectsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return ShellPage(
      title: l10n.appTitle,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.package,
              size: context.xpSizes.iconXl,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.projectEmptyTitle,
              style: context.xpType.headline.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.projectEmptyBody,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 20),
            XpButton(
              label: l10n.sidebarAddProject,
              kind: XpButtonKind.primary,
              onPressed: () => context.read<ShellCubit>().show(
                const AddProjectDestination(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
