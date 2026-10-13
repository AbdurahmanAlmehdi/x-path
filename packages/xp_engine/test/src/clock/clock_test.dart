import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('SystemClock reports the current time in UTC', () {
    final before = DateTime.now().toUtc();
    final now = const SystemClock().now();

    expect(now.isUtc, isTrue);
    expect(now.difference(before), lessThan(const Duration(seconds: 5)));
  });

  test('ManualClock stands still until advanced', () {
    final clock = ManualClock(DateTime.utc(2026));

    expect(clock.now(), DateTime.utc(2026));

    clock.advance(const Duration(hours: 2));

    expect(clock.now(), DateTime.utc(2026, 1, 1, 2));
  });
}
