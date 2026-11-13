import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/settings/bloc/dashboard_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The web dashboard: what it is, and a button that opens it in the
/// browser, signed in as this app's person (D9).
class DashboardSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final canCommand = context.canCommand;
    final state = context.watch<DashboardBloc>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.settingsDashboardBody,
                style: context.xpType.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            XpButton(
              key: const Key('settings.openDashboard'),
              label: l10n.settingsDashboardOpen,
              icon: PhosphorIconsRegular.arrowSquareOut,
              kind: XpButtonKind.primary,
              busy: state.opening,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed: state.opening || !canCommand
                  ? null
                  : () => context.read<DashboardBloc>().add(
                      const DashboardOpenRequested(),
                    ),
            ),
          ],
        ),
        if (state.error case final error?) ...[
          const SizedBox(height: 8),
          XpMessage.error(error),
        ],
      ],
    );
  }
}
