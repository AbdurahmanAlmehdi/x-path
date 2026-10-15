import 'dart:async';

import 'package:flutter/widgets.dart';

/// The time the app shows live durations against ("elapsed 6m 53s").
///
/// `XpClock.now` reads it and rebuilds the caller every second while
/// [ticking]. Without an `XpClock` above, the time is the system's and
/// nothing ticks, which keeps widget tests still; the app puts a ticking one
/// at its root.
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

  @override
  State<XpClock> createState() => _XpClockState();
}

class _XpClockState extends State<XpClock> {
  Timer? _timer;
  var _tick = 0;

  @override
  void initState() {
    super.initState();
    if (widget.ticking) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _tick++),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ClockScope(now: widget.clock, tick: _tick, child: widget.child);
}

class _ClockScope extends InheritedWidget {
  const new({required this.now, required this.tick, required super.child});

  final DateTime Function() now;
  final int tick;

  @override
  bool updateShouldNotify(_ClockScope oldWidget) =>
      tick != oldWidget.tick || now != oldWidget.now;
}
