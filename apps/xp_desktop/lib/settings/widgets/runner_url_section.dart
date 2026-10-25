import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/settings/bloc/runner_url_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The runner URL: what it is, the engine's warning about it, and a field to
/// set it. Settings shows it, and so does the pairing sheet while the engine
/// is only reachable on this Mac.
class RunnerUrlSection extends StatefulWidget {
  const new({super.key});

  @override
  State<RunnerUrlSection> createState() => _RunnerUrlSectionState();
}

class _RunnerUrlSectionState extends State<RunnerUrlSection> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final canCommand = context.canCommand;
    return BlocConsumer<RunnerUrlBloc, RunnerUrlState>(
      listenWhen: (previous, current) => previous.saved != current.saved,
      listener: (context, state) => _url.clear(),
      builder: (context, state) {
        final bloc = context.read<RunnerUrlBloc>();
        final set = state.url?.url;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsRunnerUrlBody,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (state.url != null)
              XpMessage(
                set == null ? XpStatus.scanInfo : XpStatus.credentialVerified,
                set == null
                    ? l10n.settingsRunnerUrlUnset
                    : l10n.settingsRunnerUrlSet(set),
              ),
            if (state.url?.warning case final warning?) ...[
              const SizedBox(height: 8),
              XpMessage(XpStatus.scanWarning, warning),
            ],
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              XpMessage.error(error),
            ],
            const SizedBox(height: 12),
            XpTextField(
              key: const Key('settings.runnerUrl'),
              label: l10n.settingsRunnerUrl,
              hint: 'https://mac.tailnet.ts.net',
              controller: _url,
              code: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsRunnerUrlNote,
                    style: context.xpType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (set != null) ...[
                  XpButton(
                    key: const Key('settings.runnerUrlClear'),
                    label: l10n.settingsRunnerUrlClear,
                    kind: XpButtonKind.tertiary,
                    busy: state.command == RunnerUrlCommand.clearing,
                    onPressed: state.busy || !canCommand
                        ? null
                        : () => bloc.add(const RunnerUrlCleared()),
                  ),
                  const SizedBox(width: 8),
                ],
                ListenableBuilder(
                  listenable: _url,
                  builder: (context, _) => XpButton(
                    key: const Key('settings.runnerUrlSave'),
                    label: l10n.settingsRunnerUrlSave,
                    kind: XpButtonKind.primary,
                    busy: state.command == RunnerUrlCommand.saving,
                    tooltip: canCommand ? null : l10n.readOnlyHint,
                    onPressed:
                        _url.text.trim().isEmpty || state.busy || !canCommand
                        ? null
                        : () => bloc.add(RunnerUrlSaved(_url.text)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
