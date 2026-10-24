import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/pump_app.dart';

/// Sends [state] the way the macOS embedder does: a message on the
/// lifecycle channel, from which Flutter derives the transitions.
Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
}

/// What the clock shows: the seconds of the current time, and whether live
/// motion runs.
class _Readout extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Text(
    '${XpClock.now(context).second} ${XpClock.isLive(context)}',
    textDirection: TextDirection.ltr,
  );
}

void main() {
  group('XpClock', () {
    late DateTime now;

    setUp(() => now = DateTime(2026, 10, 13, 14, 8));

    Future<void> pumpClock(WidgetTester tester, {bool ticking = true}) async {
      await lifecycle(tester, AppLifecycleState.resumed);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      await tester.pumpWidget(
        XpClock(clock: () => now, ticking: ticking, child: const _Readout()),
      );
    }

    /// Moves the fake clock and the test's timers on by [seconds].
    Future<void> wait(WidgetTester tester, int seconds) async {
      now = now.add(Duration(seconds: seconds));
      await tester.pump(Duration(seconds: seconds));
    }

    testWidgets('ticks every second while the app is in front', (tester) async {
      await pumpClock(tester);
      expect(find.text('0 true'), findsOneWidget);

      await wait(tester, 1);
      expect(find.text('1 true'), findsOneWidget);
      await wait(tester, 1);
      expect(find.text('2 true'), findsOneWidget);
    });

    for (final away in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      testWidgets('stops while ${away.name} and catches up on resume', (
        tester,
      ) async {
        await pumpClock(tester);
        await lifecycle(tester, away);
        await tester.pump();
        expect(find.text('0 false'), findsOneWidget);

        await wait(tester, 5);
        expect(find.text('0 false'), findsOneWidget, reason: 'no tick');

        await lifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
        expect(find.text('5 true'), findsOneWidget, reason: 'fresh time');

        await wait(tester, 1);
        expect(find.text('6 true'), findsOneWidget, reason: 'ticks again');
      });
    }

    testWidgets('a still clock stays still in front and away', (tester) async {
      await pumpClock(tester, ticking: false);
      await wait(tester, 2);
      expect(find.text('0 true'), findsOneWidget);

      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('2 true'), findsOneWidget, reason: 'resume rebuilds');
    });

    testWidgets('starts still when the app is already away', (tester) async {
      // Inactive, not hidden: Flutter draws no frames at all while hidden.
      await lifecycle(tester, AppLifecycleState.inactive);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      await tester.pumpWidget(
        XpClock(clock: () => now, child: const _Readout()),
      );
      await wait(tester, 3);
      expect(find.text('0 false'), findsOneWidget);

      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('3 true'), findsOneWidget);
    });

    testWidgets('a pause holds the time and motion, not the wall', (
      tester,
    ) async {
      await lifecycle(tester, AppLifecycleState.resumed);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      DateTime? pausedAt;
      late StateSetter setPause;
      await tester.pumpWidget(
        XpClock(
          clock: () => now,
          child: StatefulBuilder(
            builder: (context, setState) {
              setPause = setState;
              return XpClockPause(
                at: pausedAt,
                child: Builder(
                  builder: (context) => Text(
                    '${XpClock.now(context).second} '
                    '${XpClock.wall(context).second} '
                    '${XpClock.isLive(context)} '
                    '${XpClock.read(context).second}',
                    textDirection: TextDirection.ltr,
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('0 0 true 0'), findsOneWidget);

      setPause(() => pausedAt = now);
      await wait(tester, 3);
      expect(find.text('0 3 false 0'), findsOneWidget);

      setPause(() => pausedAt = null);
      await tester.pump();
      expect(find.text('3 3 true 3'), findsOneWidget);
    });

    testWidgets('without a clock above, the system time is live', (
      tester,
    ) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) => Text(
            '${XpClock.isLive(context)} '
            '${XpClock.wall(context).year == DateTime.now().year} '
            '${XpClock.read(context).year == DateTime.now().year}',
            textDirection: TextDirection.ltr,
          ),
        ),
      );
      expect(find.text('true true true'), findsOneWidget);
    });

    testWidgets('spinners stand still while the app is away', (tester) async {
      await lifecycle(tester, AppLifecycleState.resumed);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      await tester.pumpWidget(
        themed(
          const XpSpinner(
            icon: PhosphorIconsRegular.circleNotch,
            size: 14,
            color: Color(0xFF000000),
          ),
        ),
      );
      Animation<double> turns() => tester
          .widget<RotationTransition>(find.byType(RotationTransition))
          .turns;
      expect(turns().isAnimating, isTrue);

      await lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(turns().isAnimating, isFalse);

      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(turns().isAnimating, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
