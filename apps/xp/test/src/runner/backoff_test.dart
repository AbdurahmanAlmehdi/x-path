import 'dart:math';

import 'package:test/test.dart';
import 'package:xp/src/runner/backoff.dart';

class _Fixed implements Random {
  const new(this.fraction);

  final double fraction;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => fraction;

  @override
  int nextInt(int max) => (max * fraction).floor().clamp(0, max - 1);
}

void main() {
  test('doubles from the initial delay up to the maximum', () {
    final backoff = Backoff(random: const _Fixed(0.999));

    final delays = [for (var i = 0; i < 9; i++) backoff.next().inMilliseconds];

    // Half of each delay is fixed and half random: with the largest random
    // part, the delay is the full 1, 2, 4, ... seconds, then the maximum.
    const full = [1, 2, 4, 8, 16, 32, 60, 60, 60];
    for (final (index, delay) in delays.indexed) {
      expect(
        delay,
        closeTo(full[index] * 1000, full[index] * 5),
        reason: '$index',
      );
    }
  });

  test('is never below half of the delay and never zero', () {
    final backoff = Backoff(random: const _Fixed(0));

    final delays = [for (var i = 0; i < 4; i++) backoff.next()];

    expect(delays, [
      const Duration(milliseconds: 500),
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
  });

  test('spreads the runners that lost the engine together', () {
    final seen = {
      for (var i = 0; i < 50; i++) Backoff(random: Random(i)).next(),
    };

    expect(seen.length, greaterThan(10));
    for (final delay in seen) {
      expect(delay, greaterThanOrEqualTo(const Duration(milliseconds: 500)));
      expect(delay, lessThanOrEqualTo(const Duration(seconds: 1)));
    }
  });

  test('starts again from the initial delay after a reset', () {
    final backoff = Backoff(random: const _Fixed(0))
      ..next()
      ..next()
      ..next()
      ..reset();

    expect(backoff.next(), const Duration(milliseconds: 500));
  });

  test('keeps counting without overflow after many failures', () {
    final backoff = Backoff(random: const _Fixed(0.5));

    for (var i = 0; i < 100; i++) {
      backoff.next();
    }

    expect(backoff.next(), lessThanOrEqualTo(const Duration(seconds: 60)));
  });

  test('uses the delays it is given', () {
    final backoff = Backoff(
      initial: const Duration(milliseconds: 10),
      max: const Duration(milliseconds: 40),
      random: const _Fixed(0.999),
    );

    expect(
      [for (var i = 0; i < 4; i++) backoff.next().inMilliseconds],
      [10, 20, 40, 40],
    );
  });
}
