import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Holds live time still below it while nothing is heard from the engine
/// (reconnecting, unreachable, or refusing the token): running timers and
/// spinners stop where the engine was last heard, and `CachedChip` says
/// since when the page is cached. Back in touch, time runs again.
class EngineStaleness extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  /// When the engine was last heard, while it is not: `null` while it is,
  /// and while it was never heard in this session.
  static DateTime? lastHeard(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StaleScope>()?.lastHeard;

  /// Whether nothing is heard from the engine now.
  static bool isStale(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StaleScope>()?.stale ?? false;

  @override
  State<EngineStaleness> createState() => _EngineStalenessState();
}

const _away = <EngineStatus>{
  EngineStatus.reconnecting,
  EngineStatus.unreachable,
  EngineStatus.rejected,
};

class _EngineStalenessState extends State<EngineStaleness> {
  /// When time stopped, while the engine is away.
  DateTime? _pausedAt;

  /// Whether the engine answered in this session.
  var _heard = false;

  @override
  void initState() {
    super.initState();
    _changed(context.read<EngineConnectionBloc>().state.status);
  }

  void _changed(EngineStatus status) {
    if (!_away.contains(status)) {
      _pausedAt = null;
      _heard = _heard || status != EngineStatus.connecting;
    } else {
      _pausedAt ??= XpClock.read(context);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<EngineConnectionBloc, EngineConnectionState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) => setState(() => _changed(state.status)),
        child: _StaleScope(
          stale: _pausedAt != null,
          lastHeard: _heard ? _pausedAt : null,
          child: XpClockPause(at: _pausedAt, child: widget.child),
        ),
      );
}

class _StaleScope extends InheritedWidget {
  const new({
    required this.stale,
    required this.lastHeard,
    required super.child,
  });

  final bool stale;
  final DateTime? lastHeard;

  @override
  bool updateShouldNotify(_StaleScope oldWidget) =>
      stale != oldWidget.stale || lastHeard != oldWidget.lastHeard;
}

/// "Cached · 14:02" in a page's toolbar while the page shows what was
/// cached ([cached], from the page's snapshot) or the engine is away: the
/// time is when the engine was last heard, left out when it was not heard
/// in this session.
class CachedChip extends StatelessWidget {
  const new({required this.cached, super.key});

  final bool cached;

  @override
  Widget build(BuildContext context) {
    if (!cached && !EngineStaleness.isStale(context)) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final colors = context.xpColors;
    final since = EngineStaleness.lastHeard(context);
    return Container(
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.container(XpStatusPair.caution),
        borderRadius: BorderRadius.circular(context.xpRadii.xs),
      ),
      child: Text(
        since == null ? l10n.cached : l10n.cachedSince(formatTime(since)),
        style: context.xpType.caption.copyWith(
          color: colors.onContainer(XpStatusPair.caution),
        ),
      ),
    );
  }
}
