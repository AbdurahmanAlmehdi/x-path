import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/settings/bloc/command_line_tool_bloc.dart';
import 'package:xp_desktop/settings/bloc/github_token_bloc.dart';
import 'package:xp_desktop/settings/bloc/remove_xpath_bloc.dart';
import 'package:xp_desktop/settings/bloc/settings_bloc.dart';
import 'package:xp_desktop/settings/widgets/command_line_tool_section.dart';
import 'package:xp_desktop/settings/widgets/github_token_section.dart';
import 'package:xp_desktop/settings/widgets/remove_xpath_sheet.dart';
import 'package:xp_desktop/shell/widgets/engine_status_text.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The settings (XPath ▸ Settings…, ⌘,): the versions and the engine's
/// login item, the `xp` link, the engine's GitHub token, and "Remove
/// XPath". [github]
/// puts the cursor in the GitHub token field.
class SettingsPage extends StatelessWidget {
  const new({this.github = false, super.key});

  final bool github;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final settings = context.read<SettingsRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => SettingsBloc(
            app: services.runningApp,
            agent: services.agent,
            settings: settings,
          )..add(const SettingsStarted()),
        ),
        BlocProvider(
          create: (_) =>
              CommandLineToolBloc(linker: services.linker)
                ..add(const CommandLineToolRequested()),
        ),
        BlocProvider(
          create: (_) =>
              GitHubTokenBloc(settings: settings)
                ..add(const GitHubTokenRequested()),
        ),
        BlocProvider(
          create: (_) => RemoveXPathBloc(
            engines: services.engines,
            agent: services.agent,
            linker: services.linker,
            data: services.dataWiper,
            keychain: services.keychainWiper,
            app: services.runningApp,
          ),
        ),
      ],
      child: SettingsView(github: github),
    );
  }
}

class SettingsView extends StatelessWidget {
  const new({this.github = false, super.key});

  final bool github;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return ShellPage(
      title: l10n.settingsTitle,
      subtitle: l10n.settingsSubtitle,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _About(),
          const SizedBox(height: 20),
          XpSectionLabel(l10n.settingsCli),
          const SizedBox(height: 8),
          const XpPanel(
            padding: EdgeInsets.all(16),
            child: CommandLineToolSection(),
          ),
          const SizedBox(height: 20),
          XpSectionLabel(l10n.settingsGitHub),
          const SizedBox(height: 8),
          XpPanel(
            padding: const EdgeInsets.all(16),
            child: GitHubTokenSection(autofocus: github),
          ),
          const SizedBox(height: 20),
          XpSectionLabel(l10n.settingsRemove),
          const SizedBox(height: 8),
          XpPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsRemoveBody,
                    style: context.xpType.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                XpButton(
                  key: const Key('settings.remove'),
                  label: l10n.settingsRemoveButton,
                  icon: PhosphorIconsRegular.trash,
                  kind: XpButtonKind.destructive,
                  onPressed: () => unawaited(showRemoveXPathSheet(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the login item of the engine on this Mac says.
String agentStatusLabel(AppLocalizations l10n, AgentStatus? status) =>
    switch (status) {
      AgentStatus.enabled => l10n.settingsAgentEnabled,
      AgentStatus.notRegistered => l10n.settingsAgentNotRegistered,
      AgentStatus.requiresApproval => l10n.settingsAgentRequiresApproval,
      AgentStatus.notFound => l10n.settingsAgentNotFound,
      AgentStatus.unsupported => l10n.settingsAgentUnsupported,
      null => l10n.settingsUnknown,
    };

class _About extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<SettingsBloc>().state;
    final connection = context.watch<EngineConnectionBloc>().state;
    final engine = connection.active;
    final version = state.engineVersion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpSectionLabel(l10n.settingsAbout),
        const SizedBox(height: 8),
        XpPanel(
          child: Column(
            children: [
              _Row(
                l10n.settingsAppVersion,
                XpCode(state.appVersion ?? l10n.settingsUnknown),
              ),
              _Row(
                l10n.settingsEngine,
                Text(
                  engine == null ? l10n.settingsUnknown : engine.name,
                  style: context.xpType.body.copyWith(
                    color: context.xpColors.textPrimary,
                  ),
                ),
                trailing: engine == null ? null : XpCode('${engine.url}'),
              ),
              _Row(
                l10n.settingsEngineVersion,
                XpCode(
                  version == null
                      ? state.engineError ?? l10n.settingsUnknown
                      : l10n.settingsEngineVersionValue(
                          version.version,
                          version.apiVersion,
                        ),
                ),
              ),
              _Row(
                l10n.settingsConnection,
                XpStatusLabel(
                  engineXpStatus(connection.status),
                  engineStatusLabel(l10n, connection.status),
                ),
              ),
              _Row(
                l10n.settingsLoginItem,
                Text(
                  agentStatusLabel(l10n, state.agentStatus),
                  style: context.xpType.body.copyWith(
                    color: context.xpColors.textPrimary,
                  ),
                ),
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const new(this.label, this.value, {this.trailing, this.last = false});

  final String label;
  final Widget value;
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(bottom: BorderSide(color: context.xpColors.borderDefault)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: context.xpType.body.copyWith(
              color: context.xpColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: value),
        ),
        ?trailing,
      ],
    ),
  );
}
