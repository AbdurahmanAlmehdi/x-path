/// A source of the current time, so that time can be faked in tests.
abstract interface class Clock {
  /// The current time in UTC.
  DateTime now();
}

/// The system clock.
class SystemClock implements Clock {
  /// Creates the system clock.
  const new();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock that only moves when told to.
class ManualClock implements Clock {
  /// Creates a clock standing at [_now].
  new(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves the clock forward by [duration].
  void advance(Duration duration) => _now = _now.add(duration);
}
