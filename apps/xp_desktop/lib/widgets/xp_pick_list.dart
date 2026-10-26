import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_layout.dart';
import 'package:xp_desktop/widgets/xp_status.dart';
import 'package:xp_desktop/widgets/xp_tappable.dart';
import 'package:xp_desktop/widgets/xp_text_field.dart';

/// A column that lists [items] with their status, a field that filters
/// them, and the [selected] one highlighted: where a page picks a release
/// or a test run (U6d), instead of a dropdown.
class XpPickList<T> extends StatefulWidget {
  const new({
    required this.items,
    required this.selected,
    required this.titleOf,
    required this.onSelected,
    required this.searchHint,
    this.subtitleOf,
    this.statusOf,
    super.key,
  });

  final List<T> items;
  final T? selected;
  final String Function(T item) titleOf;
  final String? Function(T item)? subtitleOf;
  final XpStatus Function(T item)? statusOf;
  final ValueChanged<T> onSelected;
  final String searchHint;

  @override
  State<XpPickList<T>> createState() => _XpPickListState<T>();
}

class _XpPickListState<T> extends State<XpPickList<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(T item) {
    final words = _query.text
        .toLowerCase()
        .split(' ')
        .where((word) => word.isNotEmpty);
    final text = [
      widget.titleOf(item),
      ?widget.subtitleOf?.call(item),
    ].join(' ').toLowerCase();
    return words.every(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final shown = widget.items.where(_matches).toList();
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: XpTextField(
              controller: _query,
              hint: widget.searchHint,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const XpHairline(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                for (final item in shown)
                  XpTappable(
                    selected: item == widget.selected,
                    onTap: () => widget.onSelected(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: item == widget.selected
                            ? colors.surfaceSelected
                            : null,
                        borderRadius: BorderRadius.circular(context.xpRadii.md),
                      ),
                      child: Row(
                        children: [
                          if (widget.statusOf case final statusOf?) ...[
                            XpStatusIcon(statusOf(item)),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.titleOf(item),
                                  overflow: TextOverflow.ellipsis,
                                  style: type.bodyStrong.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (widget.subtitleOf?.call(item)
                                    case final subtitle?)
                                  Text(
                                    subtitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: type.caption.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
