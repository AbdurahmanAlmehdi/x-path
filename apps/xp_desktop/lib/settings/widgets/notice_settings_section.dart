import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/settings/bloc/notice_settings_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// What Settings calls a notice of [kind].
String noticeKindLabel(AppLocalizations l10n, NoticeKind kind) =>
    switch (kind) {
      NoticeKind.jobFailed => l10n.noticeJobFailed,
      NoticeKind.jobSucceeded => l10n.noticeJobSucceeded,
      NoticeKind.releaseRejected => l10n.noticeReleaseRejected,
      NoticeKind.releaseApproved => l10n.noticeReleaseApproved,
      NoticeKind.releaseLive => l10n.noticeReleaseLive,
      NoticeKind.credentialExpired => l10n.noticeCredentialExpired,
      NoticeKind.secretsLocked => l10n.noticeSecretsLocked,
      NoticeKind.runnerLost => l10n.noticeRunnerLost,
      NoticeKind.capabilityLost => l10n.noticeCapabilityLost,
      NoticeKind.jobWaiting => l10n.noticeJobWaiting,
    };

/// Settings ▸ Notifications (U6b): keep running in the menu bar, and a
/// checkbox per notice.
class NoticeSettingsSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<NoticeSettingsCubit>().state;
    final cubit = context.read<NoticeSettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        XpCheckbox(
          key: const Key('settings.keepRunning'),
          label: l10n.settingsKeepRunning,
          detail: l10n.settingsKeepRunningBody,
          value: state.keepRunning,
          onChanged: (keep) => unawaited(cubit.setKeepRunning(keep: keep)),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.settingsNoticesBody,
          style: context.xpType.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        for (final kind in NoticeKind.values)
          XpCheckbox(
            label: noticeKindLabel(l10n, kind),
            value: state.shows(kind),
            onChanged: (shown) => unawaited(cubit.show(kind, shown: shown)),
          ),
      ],
    );
  }
}
