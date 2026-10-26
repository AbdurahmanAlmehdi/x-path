import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/releases/bloc/release_board_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The texts the uploads of [release] send to the stores (U7b): "What's new"
/// for Google Play, "What to test" for Firebase testers. An upload reads them
/// when it runs, so a text saved while the release builds still goes out.
class ReleaseTextsPanel extends StatefulWidget {
  const new({required this.release, super.key});

  final Release release;

  @override
  State<ReleaseTextsPanel> createState() => _ReleaseTextsPanelState();
}

class _ReleaseTextsPanelState extends State<ReleaseTextsPanel> {
  late final _whatsNew = TextEditingController(text: widget.release.whatsNew);
  late final _whatToTest = TextEditingController(
    text: widget.release.whatToTest,
  );

  @override
  void didUpdateWidget(ReleaseTextsPanel old) {
    super.didUpdateWidget(old);
    final release = widget.release;
    // Another release, or texts saved elsewhere: show what the engine keeps,
    // unless the owner is typing.
    if (release.id != old.release.id || !_edited(old.release)) {
      _whatsNew.text = release.whatsNew ?? '';
      _whatToTest.text = release.whatToTest ?? '';
    }
  }

  @override
  void dispose() {
    _whatsNew.dispose();
    _whatToTest.dispose();
    super.dispose();
  }

  bool _edited(Release release) =>
      _whatsNew.text.trim() != (release.whatsNew ?? '') ||
      _whatToTest.text.trim() != (release.whatToTest ?? '');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final board = context.watch<ReleaseBoardBloc>().state;
    final canCommand = context.canCommand;
    final open = widget.release.state != ReleaseState.abandoned;
    final editable = canCommand && open;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XpSectionLabel(l10n.textsTitle),
          const SizedBox(height: 10),
          XpTextField(
            label: l10n.textsWhatsNew,
            controller: _whatsNew,
            maxLines: 4,
            enabled: editable,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          XpTextField(
            label: l10n.textsWhatToTest,
            controller: _whatToTest,
            maxLines: 4,
            enabled: editable,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.textsCaption,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: XpButton(
              label: l10n.textsSave,
              size: XpButtonSize.small,
              busy: board.command == ReleaseCommand.savingTexts,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed:
                  editable &&
                      board.command == ReleaseCommand.none &&
                      _edited(widget.release)
                  ? () => context.read<ReleaseBoardBloc>().add(
                      ReleaseBoardTextsSaved(
                        ReleaseTexts(
                          whatsNew: _whatsNew.text,
                          whatToTest: _whatToTest.text,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
