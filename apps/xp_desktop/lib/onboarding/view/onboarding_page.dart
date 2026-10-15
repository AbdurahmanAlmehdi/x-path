import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/engines/widgets/add_engine_form.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/onboarding/bloc/onboarding_bloc.dart';
import 'package:xp_desktop/onboarding/widgets/onboarding_step.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

/// Setting up this Mac: start the engine (and connect the app to it), link
/// `xp`, check the tools. On the first run it fills the window; from the
/// engine list it is a page of the shell.
class OnboardingPage extends StatelessWidget {
  const new({this.firstRun = false, super.key});

  /// Whether the app knows no engine yet (the page fills the window).
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    return BlocProvider(
      create: (_) => OnboardingBloc(
        agent: services.agent,
        localEngine: services.localEngine,
        engines: services.engines,
        linker: services.linker,
        tools: services.tools,
      )..add(const OnboardingStarted()),
      child: OnboardingView(firstRun: firstRun),
    );
  }
}

class OnboardingView extends StatefulWidget {
  const new({required this.firstRun, super.key});

  final bool firstRun;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  var _remote = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.firstRun) ...[
                Text(
                  l10n.onboardingTitle,
                  style: type.display.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                l10n.onboardingSubtitle,
                style: type.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 32),
              if (_remote) ...[
                const AddEngineForm(),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: XpButton(
                    label: l10n.onboardingBack,
                    kind: XpButtonKind.tertiary,
                    icon: PhosphorIconsRegular.caretLeft,
                    onPressed: () => setState(() => _remote = false),
                  ),
                ),
              ] else ...[
                const _Steps(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    XpButton(
                      label: l10n.onboardingRemote,
                      kind: XpButtonKind.tertiary,
                      onPressed: () => setState(() => _remote = true),
                    ),
                    const Spacer(),
                    BlocBuilder<OnboardingBloc, OnboardingState>(
                      buildWhen: (previous, current) =>
                          previous.connected != current.connected,
                      builder: (context, state) => XpButton(
                        label: l10n.onboardingDone,
                        kind: XpButtonKind.primary,
                        size: XpButtonSize.large,
                        onPressed: state.connected
                            ? () => context.read<EngineConnectionBloc>().add(
                                const EnginesChanged(),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (widget.firstRun) {
      return Material(color: colors.surfaceWindow, child: body);
    }
    return ShellPage(title: l10n.onboardingTitle, child: body);
  }
}

class _Steps extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<OnboardingBloc>().state;
    final bloc = context.read<OnboardingBloc>();
    final device = context.read<AppServices>().deviceName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingStep(
          number: 1,
          title: l10n.onboardingEngineTitle,
          body: l10n.onboardingEngineBody,
          progress: state.engine,
          result: _engineResult(l10n, state),
          actions: [
            XpButton(
              label: l10n.onboardingEngineButton,
              kind: state.connected
                  ? XpButtonKind.secondary
                  : XpButtonKind.primary,
              busy: state.engine == StepProgress.working,
              onPressed: () => bloc.add(
                OnboardingEngineRequested(
                  engineName: l10n.enginesLocalName,
                  tokenName: l10n.onboardingAppTokenName(device),
                ),
              ),
            ),
            if (state.agentStatus == AgentStatus.requiresApproval)
              XpButton(
                label: l10n.onboardingOpenLoginItems,
                onPressed: () =>
                    bloc.add(const OnboardingLoginItemsRequested()),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OnboardingStep(
          number: 2,
          title: l10n.onboardingCliTitle,
          body: l10n.onboardingCliBody,
          progress: state.cli,
          result: _cliResult(l10n, state.cliLink),
          actions: [
            XpButton(
              label: l10n.onboardingCliButton,
              busy: state.cli == StepProgress.working,
              onPressed: () => bloc.add(const OnboardingCliRequested()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OnboardingStep(
          number: 3,
          title: l10n.onboardingToolsTitle,
          body: l10n.onboardingToolsBody,
          progress: state.tools,
          details: state.toolChecks.isEmpty
              ? null
              : ToolChecklist(state.toolChecks),
          actions: [
            XpButton(
              label: l10n.onboardingToolsButton,
              busy: state.tools == StepProgress.working,
              onPressed: () => bloc.add(const OnboardingToolsRequested()),
            ),
          ],
        ),
      ],
    );
  }

  (XpStatus, String)? _engineResult(
    AppLocalizations l10n,
    OnboardingState state,
  ) {
    if (state.engineError case final error?) {
      return (XpStatus.engineUnreachable, l10n.onboardingEngineFailed(error));
    }
    if (state.tokenError case final error?) {
      return (XpStatus.engineUnreachable, l10n.onboardingTokenFailed(error));
    }
    if (state.connected) {
      return (XpStatus.engineConnected, l10n.onboardingEngineEnabled);
    }
    if (state.engine != StepProgress.failed) return null;
    return switch (state.agentStatus) {
      AgentStatus.requiresApproval => (
        XpStatus.engineSecretsLocked,
        l10n.onboardingEngineApproval,
      ),
      AgentStatus.unsupported => (
        XpStatus.engineUnreachable,
        l10n.onboardingEngineUnsupported,
      ),
      _ => (XpStatus.engineUnreachable, l10n.onboardingEngineNotFound),
    };
  }

  (XpStatus, String)? _cliResult(AppLocalizations l10n, CliLink? link) =>
      switch (link) {
        null || CliLink(state: CliLinkState.notLinked) => null,
        CliLink(state: CliLinkState.linked, :final path?, fellBack: true) => (
          XpStatus.credentialVerified,
          l10n.cliLinkedFallback(path),
        ),
        CliLink(state: CliLinkState.linked, :final path) => (
          XpStatus.credentialVerified,
          l10n.cliLinked(path ?? ''),
        ),
        CliLink(state: CliLinkState.missingBinary) => (
          XpStatus.scanWarning,
          l10n.cliMissing,
        ),
        CliLink(state: CliLinkState.conflict, :final path) => (
          XpStatus.scanWarning,
          l10n.cliConflict(path ?? ''),
        ),
        CliLink(state: CliLinkState.failed, :final detail) => (
          XpStatus.scanError,
          l10n.cliFailed(detail ?? ''),
        ),
      };
}
