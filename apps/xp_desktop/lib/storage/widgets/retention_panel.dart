import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/storage/bloc/storage_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// How many builds per flavor keep their files and how many days of logs
/// are kept (D-22, D-24), with Save.
class RetentionPanel extends StatefulWidget {
  const new({required this.retention, super.key});

  final RetentionSettings retention;

  @override
  State<RetentionPanel> createState() => _RetentionPanelState();
}

class _RetentionPanelState extends State<RetentionPanel> {
  late final _keep = TextEditingController(
    text: '${widget.retention.keepPerFlavor}',
  );
  late final _days = TextEditingController(text: '${widget.retention.logDays}');

  @override
  void didUpdateWidget(RetentionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retention != widget.retention) {
      _keep.text = '${widget.retention.keepPerFlavor}';
      _days.text = '${widget.retention.logDays}';
    }
  }

  @override
  void dispose() {
    _keep.dispose();
    _days.dispose();
    super.dispose();
  }

  /// The settings in the fields, if both are whole numbers of at least 1.
  RetentionSettings? get _settings {
    final keep = int.tryParse(_keep.text);
    final days = int.tryParse(_days.text);
    if (keep == null || days == null || keep < 1 || days < 1) return null;
    return RetentionSettings(keepPerFlavor: keep, logDays: days);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<StorageBloc>().state;
    final settings = _settings;
    final changed = settings != null && settings != widget.retention;
    final canCommand = context.canCommand;
    Widget field(String label, TextEditingController controller) => SizedBox(
      width: 200,
      child: XpTextField(
        label: label,
        controller: controller,
        code: true,
        onChanged: (_) => setState(() {}),
      ),
    );
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageRetentionTitle,
            style: context.xpType.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.storageRetentionBody,
            style: context.xpType.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              field(l10n.storageKeepPerFlavor, _keep),
              field(l10n.storageLogDays, _days),
              XpButton(
                label: l10n.storageSaveRetention,
                busy: state.command == StorageCommand.saving,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed: canCommand && changed
                    ? () => context.read<StorageBloc>().add(
                        StorageRetentionChanged(settings),
                      )
                    : null,
              ),
            ],
          ),
          if (settings == null) ...[
            const SizedBox(height: 8),
            XpMessage(XpStatus.scanWarning, l10n.storageRetentionInvalid),
          ],
        ],
      ),
    );
  }
}
