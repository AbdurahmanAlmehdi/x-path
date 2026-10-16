import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/onboarding/widgets/cli_link_message.dart';
import 'package:xp_desktop/settings/bloc/command_line_tool_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

/// Where `xp` is linked, with "Link xp" when it is not (or "Link xp again"
/// when the link points into another copy of XPath). Onboarding links it the
/// same way; this is where to do it once onboarding is over.
class CommandLineToolSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<CommandLineToolBloc>().state;
    final link = state.link;
    final (status, text) = link == null
        ? (XpStatus.scanInfo, l10n.cliChecking)
        : cliLinkMessage(l10n, link) ??
              (XpStatus.credentialMissing, l10n.cliNotLinked);
    final canLink = switch (link?.state) {
      null || CliLinkState.linked || CliLinkState.missingBinary => false,
      _ => true,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              PhosphorIconsRegular.terminalWindow,
              size: context.xpSizes.iconLg,
              color: colors.textPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.onboardingCliBody,
                style: context.xpType.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: XpMessage(
                status,
                text,
                key: const Key('settings.cliStatus'),
              ),
            ),
            if (canLink) ...[
              const SizedBox(width: 12),
              XpButton(
                key: const Key('settings.cliLink'),
                label: link?.state == CliLinkState.elsewhere
                    ? l10n.cliRelink
                    : l10n.onboardingCliButton,
                kind: XpButtonKind.primary,
                busy: state.linking,
                onPressed: state.linking
                    ? null
                    : () => context.read<CommandLineToolBloc>().add(
                        const CommandLineToolLinkRequested(),
                      ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
