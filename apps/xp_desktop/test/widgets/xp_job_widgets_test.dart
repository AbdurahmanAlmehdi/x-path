import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/pump_app.dart';

void main() {
  group('formats', () {
    test('durations', () {
      expect(formatDuration(const Duration(milliseconds: 400)), '0.4s');
      expect(formatDuration(const Duration(seconds: 41)), '41s');
      expect(formatDuration(const Duration(minutes: 6, seconds: 2)), '6m 02s');
      expect(formatDuration(const Duration(hours: 1, minutes: 4)), '1h 04m');
      expect(formatDuration(const Duration(seconds: -3)), '0s');
      expect(elapsed(null, null, DateTime(2026)), isNull);
      expect(
        elapsed(DateTime(2026), null, DateTime(2026, 1, 1, 0, 1)),
        const Duration(minutes: 1),
      );
    });

    test('counts and relative times', () {
      expect(formatCount(1284), '1,284');
      final now = DateTime(2026, 10, 13, 14, 8);
      String relative(DateTime time) => formatRelative(
        time,
        now,
        justNow: 'just now',
        ago: (duration) => '$duration ago',
        yesterday: (time) => 'Yesterday $time',
      );
      expect(relative(now.subtract(const Duration(seconds: 20))), 'just now');
      expect(relative(now.subtract(const Duration(minutes: 4))), '4m ago');
      expect(relative(now.subtract(const Duration(hours: 2))), '2h ago');
      expect(relative(DateTime(2026, 10, 12, 9, 30)), 'Yesterday 09:30');
      expect(relative(DateTime(2026, 10, 11, 9, 30)), 'Oct 11 09:30');
    });

    test('times within a day, else dates, and in full', () {
      final now = DateTime(2026, 10, 13, 14, 8);
      expect(formatWhen(DateTime(2026, 10, 13, 9, 5), now), '09:05');
      expect(formatWhen(DateTime(2026, 10, 11, 9, 5), now), 'Oct 11 09:05');
      final time = DateTime(2026, 10, 13, 14, 2, 41);
      expect(
        formatAbsolute(time),
        'Tue, Oct 13, 2026 14:02:41 ${time.timeZoneName}',
      );
    });

    test('times, SHAs, versions and sizes', () {
      expect(formatTime(DateTime(2026, 10, 13, 9, 5)), '09:05');
      expect(formatClock(DateTime(2026, 10, 13, 9, 5, 7)), '09:05:07');
      expect(shortSha('9a3bc0d4e5'), '9a3bc0d');
      expect(shortSha('abc'), 'abc');
      expect(versionLabel('5.4.1', 3283), '5.4.1 (3283)');
      expect(versionLabel('5.4.1'), '5.4.1');
      expect(pubspecLabel('5.5.0+3284'), '5.5.0 (3284)');
      expect(pubspecLabel('5.5.0'), '5.5.0');
      expect(formatSize(812), '812 B');
      expect(formatSize(812000), '812 KB');
      expect(formatSize(38900000000), '38.9 GB');
    });
  });

  group('XpClock', () {
    testWidgets('ticks every second and stops when disposed', (tester) async {
      var now = DateTime(2026, 10, 13, 14);
      final seen = <DateTime>[];
      await tester.pumpWidget(
        XpClock(
          clock: () => now,
          child: Builder(
            builder: (context) {
              seen.add(XpClock.now(context));
              return const SizedBox();
            },
          ),
        ),
      );
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(seen, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reads the system time without a clock above', (tester) async {
      DateTime? seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = XpClock.now(context);
            return const SizedBox();
          },
        ),
      );
      expect(seen, isNotNull);
    });
  });

  group('XpSegmented and XpChip', () {
    testWidgets('pick values and stay still when disabled', (tester) async {
      String? picked;
      bool? toggled;
      await tester.pumpApp(
        Column(
          children: [
            XpSegmented<String>(
              value: 'a',
              values: const ['a', 'b'],
              labelOf: (value) => value.toUpperCase(),
              onChanged: (value) => picked = value,
            ),
            XpSegmented<String>(
              value: 'c',
              values: const ['c'],
              labelOf: (value) => value,
              onChanged: null,
            ),
            XpChip(
              label: 'iOS',
              icon: PhosphorIconsRegular.appleLogo,
              selected: true,
              onChanged: (value) => toggled = value,
            ),
            const XpChip(label: 'off', selected: false, onChanged: null),
            XpButton(
              label: 'Cancel run',
              kind: XpButtonKind.destructive,
              hint: '⌘.',
              onPressed: () {},
            ),
          ],
        ),
      );
      await tester.tap(find.text('B'));
      await tester.tap(find.text('iOS'));
      await tester.tap(find.text('c'));
      await tester.tap(find.text('off'));
      expect(picked, 'b');
      expect(toggled, isFalse);
    });
  });
}
