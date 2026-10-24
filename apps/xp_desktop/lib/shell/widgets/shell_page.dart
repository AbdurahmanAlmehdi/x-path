import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/shell/widgets/connection_banner.dart';
import 'package:xp_desktop/shell/widgets/engine_staleness.dart';
import 'package:xp_desktop/theme/theme.dart';

/// One page of the content area: the toolbar (`size.toolbar.height`,
/// `surface.base`, a hairline under it) with the page's [title], [subtitle]
/// and [actions], the connection banner, then [child]. A page that shows
/// the engine's data passes [cached], so the toolbar says when what it shows
/// is cached (`CachedChip`).
///
/// The page takes the keyboard focus when it opens (unless a page above it
/// took it first), so the shell's shortcuts (⌘N, ⌘1–⌘9) work on every page.
class ShellPage extends StatelessWidget {
  const new({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.cached,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  /// Whether the page's snapshot came from the cache; `null` for a page
  /// that shows nothing of the engine's.
  final bool? cached;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: context.xpSizes.toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colors.surfaceBase,
            border: Border(bottom: BorderSide(color: colors.borderDefault)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: type.title.copyWith(color: colors.textPrimary),
                      ),
                    ),
                    if (subtitle case final subtitle?) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (cached case final cached?) CachedChip(cached: cached),
                  ],
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
          ),
        ),
        const ConnectionBanner(),
        Expanded(child: child),
      ],
    );
    return Focus(autofocus: true, skipTraversal: true, child: page);
  }
}

/// Whether the active engine takes commands now (else the app is
/// read-only).
extension CanCommand on BuildContext {
  bool get canCommand => watch<EngineConnectionBloc>().state.status.canCommand;
}
