import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/releases/widgets/release_panels.dart';
import 'package:xp_desktop/settings/bloc/cli_token_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The command that connects `xp` to the engine at [url]. It asks for the
/// token, so that the token stays out of the shell history.
String connectCommand(Uri url) => 'xp connect $url';

/// The MCP config that runs `xp mcp` on the engine at [url] with [token], as
/// agents read it (`mcpServers`).
String mcpConfig(Uri url, String token) =>
    const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'xpath': {
          'command': 'xp',
          'args': ['mcp'],
          'env': {'XP_ENGINE_URL': '$url', 'XP_MCP_TOKEN': token},
        },
      },
    });

/// Settings ▸ CLI and agents (U5b): "New token" for `xp` or for an agent,
/// then the ready-to-paste `xp connect …` command or MCP config, shown once.
class CliTokenSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final device = context.read<AppServices>().deviceName;
    final url = context.watch<EngineConnectionBloc>().state.active?.url;
    final canCommand = context.canCommand;
    return BlocBuilder<CliTokenBloc, CliTokenState>(
      builder: (context, state) {
        final bloc = context.read<CliTokenBloc>();
        XpButton create(DeviceTokenKind kind, String label, String name) =>
            XpButton(
              label: label,
              icon: PhosphorIconsRegular.plus,
              busy: state.creating == kind,
              onPressed: canCommand && state.creating == null
                  ? () => bloc.add(CliTokenRequested(name: name, kind: kind))
                  : null,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsTokensBody,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                create(
                  DeviceTokenKind.cli,
                  l10n.settingsTokensNewCli,
                  l10n.settingsTokensCliName(device),
                ),
                create(
                  DeviceTokenKind.mcp,
                  l10n.settingsTokensNewMcp,
                  l10n.settingsTokensMcpName(device),
                ),
              ],
            ),
            if (state.error case final error?) ...[
              const SizedBox(height: 12),
              XpMessage.error(error),
            ],
            if ((state.created, url) case (final created?, final url?)) ...[
              const SizedBox(height: 12),
              _Created(created, url: url),
            ],
          ],
        );
      },
    );
  }
}

class _Created extends StatelessWidget {
  const new(this.created, {required this.url});

  final CreatedToken created;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final cli = created.info.kind == DeviceTokenKind.cli;
    final text = cli ? connectCommand(url) : mcpConfig(url, created.token);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpMessage(
          XpStatus.credentialVerified,
          cli
              ? l10n.settingsTokensCliMade(created.info.name)
              : l10n.settingsTokensMcpMade(created.info.name),
        ),
        const SizedBox(height: 8),
        Container(
          key: const Key('settings.tokens.text'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(context.xpRadii.sm),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: SelectableText(
            text,
            style: context.xpType.code.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.settingsTokensOnce,
                style: context.xpType.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            CopyButton(
              label: cli
                  ? l10n.settingsTokensCopyCommand
                  : l10n.settingsTokensCopyConfig,
              text: text,
            ),
            if (cli) ...[
              const SizedBox(width: 8),
              CopyButton(
                label: l10n.settingsTokensCopyToken,
                text: created.token,
              ),
            ],
            const SizedBox(width: 8),
            XpButton(
              label: l10n.settingsTokensDone,
              size: XpButtonSize.small,
              onPressed: () =>
                  context.read<CliTokenBloc>().add(const CliTokenDismissed()),
            ),
          ],
        ),
      ],
    );
  }
}
