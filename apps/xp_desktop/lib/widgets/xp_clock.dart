import 'dart:async';

import 'package:flutter/widgets.dart';

/// The time the app shows live durations against ("elapsed 6m 53s").
///
/// `XpClock.now` reads it and rebuilds the caller every second while
/// [ticking]. Without an `XpClock` above, the time is the system's and
/// nothing ticks, which keeps widget tests still; the app puts a ticking one
/// at its root.
///
/// Live motion only runs while the app is in front (`resumed`): when macOS
/// reports XPath inactive, hidden or minimised, the clock stops and
/// [XpClock.isLive] turns false so spinners stand still, and XPath draws no
/// frames of its own in the background (each one is a chance to hit the
/// Impeller crash of flutter/flutter#185394). Back in front, every live
/// duration is rebuilt at once against the current time.
class XpClock extends StatefulWidget {
  const new({
    required this.child,
    this.clock = DateTime.now,
    this.ticking = true,
    super.key,
  });

  final Widget child;

  /// Reads the current time.
  final DateTime Function() clock;

  /// Whether durations tick every second (Formatting: "Live durations tick
  /// each second").
  final bool ticking;

  /// The current time, rebuilding [context] on every tick.
  static DateTime now(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ClockScope>();
    return scope == null ? DateTime.now() : scope.now();
  }

  /// The time of the wall, which goes on under an [XpClockPause]: for
  /// deadlines, such as when an approval expires, that do not wait for the
  /// engine. Rebuilds [context] on every tick.
  static DateTime wall(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ClockScope>();
    return scope == null ? DateTime.now() : scope.wall();
  }

  /// The current time, without rebuilding [context] on every tick: for an
  /// event handler that notes when something happened.
  static DateTime read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_ClockScope>();
    return scope == null ? DateTime.now() : scope.now();
  }

  /// Whether the app is in front, so live motion may run; rebuilds [context]
  /// when that changes. True without an `XpClock` above.
  static bool isLive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiveScope>()?.live ?? true;

  @override
  State<XpClock> createState() => _XpClockState();
}

class _XpClockState extends State<XpClock> {
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  var _tick = 0;
  var _live = true;

  @override
  void initState() {
    super.initState();
    _live = _inFront(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
    _schedule();
  }

  /// Before the first lifecycle message the app counts as in front.
  static bool _inFront(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _onLifecycleChanged(AppLifecycleState state) {
    final live = _inFront(state);
    if (live == _live) return;
    setState(() {
      _live = live;
      // Back in front: show the time that passed while the app was away.
      if (live) _tick++;
    });
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = widget.ticking && _live
        ? Timer.periodic(
            const Duration(seconds: 1),
            (_) => setState(() => _tick++),
          )
        : null;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LiveScope(
    live: _live,
    child: _ClockScope(
      now: widget.clock,
      wall: widget.clock,
      tick: _tick,
      child: widget.child,
    ),
  );
}

class _ClockScope extends InheritedWidget {
  const new({
    required this.now,
    required this.wall,
    required this.tick,
    required super.child,
  });

  final DateTime Function() now;
  final DateTime Function() wall;
  final int tick;

  @override
  bool updateShouldNotify(_ClockScope oldWidget) =>
      tick != oldWidget.tick || now != oldWidget.now;
}

class _LiveScope extends InheritedWidget {
  const new({required this.live, required super.child});

  final bool live;

  @override
  bool updateShouldNotify(_LiveScope oldWidget) => live != oldWidget.live;
}

/// Holds the time still at [at] below it while [at] is set: live durations
/// stop there and spinners stand still, as while the app is away; the wall
/// (`XpClock.wall`) goes on ticking. The shell
/// holds it while the engine is away, so a running job does not seem to run
/// on (or end) while nothing is heard of it.
class XpClockPause extends StatelessWidget {
  const new({required this.at, required this.child, super.key});

  /// When the time stopped, or `null` while it runs.
  final DateTime? at;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final at = this.at;
    if (at == null) return child;
    final outer = context.dependOnInheritedWidgetOfExactType<_ClockScope>();
    return _LiveScope(
      live: false,
      child: _ClockScope(
        now: () => at,
        wall: outer?.wall ?? DateTime.now,
        tick: outer?.tick ?? 0,
        child: child,
      ),
    );
  }
}
