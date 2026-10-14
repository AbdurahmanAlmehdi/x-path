import 'dart:math';

/// The delays between attempts to connect: exponential, with jitter.
///
/// The delay after the n-th failure in a row is `initial * 2^n`, at most
/// [max]; half of it is fixed and half is random ("equal jitter"), so a crowd
/// of runners that lost the same engine does not come back in step, and no
/// delay is ever near zero.
class Backoff {
  /// Creates a backoff. [random] is for tests.
  new({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 60),
    Random? random,
  }) : _random = random ?? Random();

  /// The delay after the first failure, before jitter.
  final Duration initial;

  /// The longest delay, before jitter.
  final Duration max;

  final Random _random;
  var _failures = 0;

  /// The delay to wait now, after one more failure.
  Duration next() {
    final exponent = _failures < 20 ? _failures : 20;
    _failures++;
    final scaled = initial.inMilliseconds * (1 << exponent);
    final capped = scaled < max.inMilliseconds ? scaled : max.inMilliseconds;
    final half = capped ~/ 2;
    return Duration(milliseconds: half + _random.nextInt(half + 1));
  }

  /// A connection worked: the next failure starts from [initial] again.
  void reset() => _failures = 0;
}
