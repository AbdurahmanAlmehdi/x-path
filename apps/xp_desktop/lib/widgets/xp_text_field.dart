import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_layout.dart';

/// A labelled field: a `type.label` caption over a well
/// (`surface.sunken`, hairline, `radius.md`) with the accent ring on focus.
/// Without a [label] the well stands alone, for fields whose caption sits
/// beside them.
class XpTextField extends StatelessWidget {
  const new({
    required this.controller,
    this.label,
    this.hint,
    this.obscure = false,
    this.code = false,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.trailing,
    this.focusNode,
    super.key,
  });

  final String? label;
  final TextEditingController controller;
  final String? hint;

  /// Hides the text (tokens, passwords).
  final bool obscure;

  /// Sets the text in `type.code` (paths, URLs, identifiers).
  final bool code;
  final int maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// Beside the field, for example a "Choose…" button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final radius = BorderRadius.circular(context.xpRadii.md);
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    final style = (code ? type.code : type.body).copyWith(
      color: colors.textPrimary,
    );
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      enabled: enabled,
      maxLines: obscure ? 1 : maxLines,
      minLines: 1,
      onChanged: onChanged,
      style: style,
      cursorColor: colors.accentDefault,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: style.copyWith(color: colors.textTertiary),
        filled: true,
        fillColor: colors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        border: outline(colors.borderDefault),
        enabledBorder: outline(colors.borderDefault),
        disabledBorder: outline(colors.borderSubtle),
        focusedBorder: outline(colors.focusRing, context.xpBorders.widthFocus),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label case final label?) ...[
          XpSectionLabel(label),
          const SizedBox(height: 6),
        ],
        if (trailing case final trailing?)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: field),
              const SizedBox(width: 8),
              trailing,
            ],
          )
        else
          field,
      ],
    );
  }
}
