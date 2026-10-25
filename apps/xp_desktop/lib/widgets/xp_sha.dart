import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_format.dart';

/// A commit as the UI shows it, `9a3bc0d`, that copies the whole [sha] when
/// clicked; its tooltip names the whole commit, then says "Copied".
class XpSha extends StatefulWidget {
  const new(this.sha, {this.style, super.key});

  final String sha;

  /// Defaults to `type.code` in the secondary text colour.
  final TextStyle? style;

  @override
  State<XpSha> createState() => _XpShaState();
}

class _XpShaState extends State<XpSha> {
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sha));
    if (!mounted) return;
    _reset?.cancel();
    setState(() {
      _reset = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _reset = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: _reset == null ? l10n.copyHint(widget.sha) : l10n.copied,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _copy,
          child: Text(
            shortSha(widget.sha),
            style:
                widget.style ??
                context.xpType.code.copyWith(
                  color: context.xpColors.textSecondary,
                ),
          ),
        ),
      ),
    );
  }
}
