import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_desktop/settings/bloc/cli_token_bloc.dart';
import 'package:xp_desktop/settings/bloc/command_line_tool_bloc.dart';
import 'package:xp_desktop/settings/bloc/notice_settings_cubit.dart';
import 'package:xp_desktop/settings/bloc/remove_xpath_bloc.dart';
import 'package:xp_desktop/settings/bloc/runner_url_bloc.dart';
import 'package:xp_desktop/settings/bloc/settings_bloc.dart';
import 'package:xp_desktop/settings/widgets/cli_token_section.dart';
import 'package:xp_desktop/settings/widgets/command_line_tool_section.dart';
import 'package:xp_desktop/settings/widgets/notice_settings_section.dart';
import 'package:xp_desktop/settings/widgets/remove_xpath_sheet.dart';
import 'package:xp_desktop/settings/widgets/runner_url_section.dart';
import 'package:xp_desktop/shell/widgets/engine_status_text.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The settings (XPath ▸ Settings…, ⌘,): the versions and the engine's
/// login item, the `xp` link, tokens for `xp` and agents, the runner URL,
/// notifications, and "Remove XPath". The GitHub token is in Credentials.
class SettingsPage extends StatelessWidget {
  const new({super.key});

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
        BlocProvider(create: (_) => CliTokenBloc(settings: settings)),
        BlocProvider(
          create: (_) => NoticeSettingsCubit(
            preferences: services.preferences,
            app: services.runningApp,
          ),
        ),
        BlocProvider(
          create: (_) =>
              RunnerUrlBloc(runners: context.read<RunnersRepository>())
                ..add(const RunnerUrlRequested()),
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
      child: const SettingsView(),
    );
  }
}

class SettingsView extends StatelessWidget {
  const new({super.key});

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
          XpSectionLabel(l10n.settingsTokens),
          const SizedBox(height: 8),
          const XpPanel(padding: EdgeInsets.all(16), child: CliTokenSection()),
          const SizedBox(height: 20),
          XpSectionLabel(l10n.settingsRunners),
          const SizedBox(height: 8),
          const XpPanel(padding: EdgeInsets.all(16), child: RunnerUrlSection()),
          const SizedBox(height: 20),
          XpSectionLabel(l10n.settingsNotices),
          const SizedBox(height: 8),
          const XpPanel(
            padding: EdgeInsets.all(16),
            child: NoticeSettingsSection(),
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

class _About extends StatefulWidget {
  const new();

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  @override
  void initState() {
    super.initState();
    context.read<LocalEngineBloc>().add(const LocalEngineChecked());
  }

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
              _LocalEngineRow(
                agentStatus: state.agentStatus,
                setUp: connection.engines.any((engine) => engine.isLocal),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Engine on this Mac": Running or Not running, from whether it answers,
/// with "Start engine" when it is set up and does not answer. Until that is
/// known, or when this Mac has no engine set up, what its login item says.
class _LocalEngineRow extends StatelessWidget {
  const new({required this.agentStatus, required this.setUp});

  final AgentStatus? agentStatus;
  final bool setUp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final local = context.watch<LocalEngineBloc>().state;
    final bloc = context.read<LocalEngineBloc>();
    final failure = localEngineFailureText(l10n, local);
    final Widget value = switch (local.running) {
      _ when local.starting => XpStatusLabel(
        XpStatus.engineReconnecting,
        l10n.localEngineStarting,
      ),
      true => XpStatusLabel(XpStatus.engineConnected, l10n.localEngineRunning),
      false when setUp => XpStatusLabel(
        XpStatus.engineUnreachable,
        l10n.localEngineNotRunning,
      ),
      _ => Text(
        agentStatusLabel(l10n, agentStatus),
        style: context.xpType.body.copyWith(
          color: context.xpColors.textPrimary,
        ),
      ),
    };
    final canStart = setUp && local.running == false;
    return _Row(
      l10n.settingsLoginItem,
      failure == null
          ? value
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                value,
                const SizedBox(height: 6),
                XpMessage(XpStatus.engineUnreachable, failure),
              ],
            ),
      trailing: !canStart && !local.starting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (local.failure == LocalEngineFailure.needsApproval) ...[
                  XpButton(
                    label: l10n.onboardingOpenLoginItems,
                    size: XpButtonSize.small,
                    onPressed: () =>
                        bloc.add(const LocalEngineLoginItemsRequested()),
                  ),
                  const SizedBox(width: 8),
                ],
                XpButton(
                  key: const Key('settings.startEngine'),
                  label: l10n.localEngineStart,
                  kind: XpButtonKind.primary,
                  size: XpButtonSize.small,
                  busy: local.starting,
                  onPressed: local.starting
                      ? null
                      : () => bloc.add(
                          LocalEngineStartRequested(
                            tokenName: LocalEngineListener.tokenName(context),
                          ),
                        ),
                ),
              ],
            ),
      last: true,
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
        ConstrainedBox(
          // Grows with the text size (U6c).
          constraints: const BoxConstraints(minWidth: 180),
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
