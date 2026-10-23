import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/settings/bloc/github_token_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The engine's GitHub token: what GitHub says of it, a field to paste a
/// new one, "Import from GitHub CLI" and "Remove token". The token is never
/// shown; the field clears once the engine stored it.
class GitHubTokenSection extends StatefulWidget {
  const new({this.autofocus = false, super.key});

  /// Puts the cursor in the token field.
  final bool autofocus;

  @override
  State<GitHubTokenSection> createState() => _GitHubTokenSectionState();
}

class _GitHubTokenSectionState extends State<GitHubTokenSection> {
  final _token = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final canCommand = context.canCommand;
    return BlocConsumer<GitHubTokenBloc, GitHubTokenState>(
      listenWhen: (previous, current) => previous.saved != current.saved,
      listener: (context, state) => _token.clear(),
      builder: (context, state) {
        final bloc = context.read<GitHubTokenBloc>();
        final stored = state.status?.stored ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIconsRegular.githubLogo,
                  size: context.xpSizes.iconLg,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.settingsGitHubBody,
                    style: context.xpType.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _status(context, state),
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              XpMessage(XpStatus.scanError, l10n.settingsGitHubFailed(error)),
            ],
            const SizedBox(height: 16),
            XpTextField(
              key: const Key('settings.githubToken'),
              label: l10n.settingsGitHubToken,
              hint: l10n.settingsGitHubTokenHint,
              controller: _token,
              focusNode: _focus,
              obscure: true,
              code: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsGitHubImportNote,
                    style: context.xpType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (stored) ...[
                  XpButton(
                    key: const Key('settings.githubRemove'),
                    label: l10n.settingsGitHubRemove,
                    kind: XpButtonKind.tertiary,
                    busy: state.command == GitHubTokenCommand.clearing,
                    onPressed: state.busy || !canCommand
                        ? null
                        : () async {
                            final confirmed = await confirmAction(
                              context,
                              title: l10n.settingsGitHubRemoveTitle,
                              points: [
                                l10n.settingsGitHubRemoveStops,
                                l10n.settingsGitHubRemoveKeeps,
                              ],
                              keep: l10n.confirmKeep,
                              confirm: l10n.settingsGitHubRemove,
                            );
                            if (confirmed) {
                              bloc.add(const GitHubTokenCleared());
                            }
                          },
                  ),
                  const SizedBox(width: 8),
                ],
                XpButton(
                  key: const Key('settings.githubImport'),
                  label: l10n.settingsGitHubImport,
                  icon: PhosphorIconsRegular.terminalWindow,
                  busy: state.command == GitHubTokenCommand.importing,
                  onPressed: state.busy || !canCommand
                      ? null
                      : () => bloc.add(const GitHubTokenImported()),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _token,
                  builder: (context, _) => XpButton(
                    key: const Key('settings.githubSave'),
                    label: l10n.settingsGitHubSave,
                    kind: XpButtonKind.primary,
                    busy: state.command == GitHubTokenCommand.saving,
                    tooltip: canCommand ? null : l10n.readOnlyHint,
                    onPressed:
                        _token.text.trim().isEmpty || state.busy || !canCommand
                        ? null
                        : () => bloc.add(GitHubTokenSaved(_token.text.trim())),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _status(BuildContext context, GitHubTokenState state) {
    final l10n = context.l10n;
    final status = state.status;
    if (status == null) {
      return XpMessage(XpStatus.scanInfo, l10n.settingsGitHubChecking);
    }
    if (!status.stored) {
      return XpMessage(XpStatus.credentialMissing, l10n.settingsGitHubMissing);
    }
    final said = [?status.message, ?status.fix].join(' ');
    return switch (status.status) {
      CredentialStatus.rejected => XpMessage(
        XpStatus.credentialExpired,
        l10n.settingsGitHubRejected(said),
      ),
      CredentialStatus.unreachable || CredentialStatus.unverified => XpMessage(
        XpStatus.scanWarning,
        l10n.settingsGitHubUnreachable(said),
      ),
      _ => XpMessage(
        XpStatus.credentialVerified,
        status.login == null
            ? l10n.settingsGitHubConnectedNoLogin
            : l10n.settingsGitHubConnected(status.login!),
      ),
    };
  }
}
