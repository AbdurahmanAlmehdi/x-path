import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/releases/widgets/release_panels.dart'
    show CopyButton;
import 'package:xp_desktop/runners/bloc/pair_runner_bloc.dart';
import 'package:xp_desktop/settings/bloc/runner_url_bloc.dart';
import 'package:xp_desktop/settings/widgets/runner_url_section.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Opens the pairing sheet: a name, then a single-use pairing token (D-08)
/// and the command to run on the new machine. The command names the runner
/// URL the token carries, else the address of this app's engine; when that
/// one only works on this Mac, the sheet says so and lets the owner set the
/// runner URL in place.
Future<void> showPairRunnerSheet(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: context.xpColors.scrimDefault,
  builder: (_) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: context.read<EngineConnectionBloc>()),
      BlocProvider(
        create: (_) =>
            PairRunnerBloc(runners: context.read<RunnersRepository>()),
      ),
      BlocProvider(
        create: (_) =>
            RunnerUrlBloc(runners: context.read<RunnersRepository>()),
      ),
    ],
    child: const PairRunnerSheet(),
  ),
);

class PairRunnerSheet extends StatefulWidget {
  const new({super.key});

  @override
  State<PairRunnerSheet> createState() => _PairRunnerSheetState();
}

class _PairRunnerSheetState extends State<PairRunnerSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    if (_name.text.trim().isEmpty) return;
    context.read<PairRunnerBloc>().add(PairingTokenRequested(_name.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final state = context.watch<PairRunnerBloc>().state;
    final token = state.token;
    final engine = context.select<EngineConnectionBloc, Uri?>(
      (bloc) => bloc.state.active?.url,
    );
    return Dialog(
      backgroundColor: colors.surfaceOverlay,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.xpRadii.lg),
        side: BorderSide(color: colors.borderStrong),
      ),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pairRunnerTitle,
                style: type.headline.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.pairRunnerBody,
                style: type.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (token == null) ...[
                XpTextField(
                  label: l10n.pairRunnerName,
                  controller: _name,
                  hint: 'mac-mini',
                  code: true,
                  onChanged: (_) => setState(() {}),
                ),
                if (state.error case final error?) ...[
                  const SizedBox(height: 10),
                  XpMessage(XpStatus.scanError, error),
                ],
              ] else
                _Token(
                  token: token,
                  command: PairingCommand.of(
                    token,
                    fallback: engine ?? Uri(),
                    runnerUrl: context.select<RunnerUrlBloc, String?>(
                      (bloc) => bloc.state.url?.url,
                    ),
                  ),
                  onNewToken: () => context.read<PairRunnerBloc>().add(
                    PairingTokenRequested(token.name),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  XpButton(
                    label: token == null
                        ? l10n.pairRunnerCancel
                        : l10n.pairRunnerDone,
                    size: XpButtonSize.large,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (token == null) ...[
                    const SizedBox(width: 8),
                    XpButton(
                      label: l10n.pairRunnerCreate,
                      kind: XpButtonKind.primary,
                      size: XpButtonSize.large,
                      busy: state.status == PairRunnerStatus.creating,
                      onPressed: _name.text.trim().isEmpty ? null : _create,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Token extends StatelessWidget {
  const new({
    required this.token,
    required this.command,
    required this.onNewToken,
  });

  final PairingToken token;

  /// What the runner machine runs.
  final PairingCommand command;

  final VoidCallback onNewToken;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final now = XpClock.now(context);
    final expiresAt = token.expiresAt;
    final expired = !expiresAt.isAfter(now);
    Widget well(String text, String copyLabel) => Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: type.code.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          CopyButton(label: copyLabel, text: text),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpSectionLabel(l10n.pairRunnerToken(token.name)),
        const SizedBox(height: 6),
        well(token.token, l10n.pairRunnerCopyToken),
        const SizedBox(height: 14),
        XpSectionLabel(l10n.pairRunnerCommand),
        const SizedBox(height: 6),
        well(command.text, l10n.pairRunnerCopyCommand),
        const SizedBox(height: 12),
        if (command.onlyHere) ...[
          XpMessage(XpStatus.scanWarning, l10n.pairRunnerLoopback),
          const SizedBox(height: 12),
          const RunnerUrlSection(),
          const SizedBox(height: 12),
        ],
        if (expired)
          Row(
            children: [
              Expanded(
                child: XpMessage(
                  XpStatus.approvalExpired,
                  l10n.pairRunnerExpired,
                ),
              ),
              const SizedBox(width: 8),
              XpButton(
                key: const Key('pairRunner.newToken'),
                label: l10n.pairRunnerNewToken,
                onPressed: onNewToken,
              ),
            ],
          )
        else
          XpMessage(
            expiresAt.difference(now) < const Duration(minutes: 5)
                ? XpStatus.credentialExpiring
                : XpStatus.scanInfo,
            l10n.pairRunnerExpires(
              formatCountdown(expiresAt, now),
              formatTime(expiresAt),
            ),
          ),
      ],
    );
  }
}
