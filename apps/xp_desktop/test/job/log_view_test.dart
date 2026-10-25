import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/job.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';

void main() {
  final steps = runningRun().jobs[1].steps;

  Future<void> pumpLog(
    WidgetTester tester, {
    List<JobStep>? jobSteps,
    List<LogLineFrame>? lines,
    bool live = true,
  }) async {
    await tester.pumpApp(
      LogView(
        steps: jobSteps ?? steps,
        lines: lines ?? iosLog,
        title: 'Build prod for ios',
        status: XpStatus.jobRunning,
        live: live,
      ),
    );
    await tester.pump();
  }

  Finder text(String text) => find.text(text, findRichText: true);

  group('LogView', () {
    testWidgets('opens the running step and counts the lines of the rest', (
      tester,
    ) async {
      await pumpLog(tester);
      expect(text('Running pod install...'), findsOneWidget);
      expect(text('Checking out 9a3bc0d'), findsNothing);
      expect(find.text('2 lines'), findsOneWidget);
      expect(find.text('1 line'), findsOneWidget);
      expect(find.text('14:03:09'), findsOneWidget);
    });

    testWidgets('copies a line with where it is', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.pumpApp(
        LogView(
          jobId: 'job_ios',
          steps: steps,
          lines: iosLog,
          title: 'Build prod for ios',
          live: true,
        ),
      );
      await tester.pump();
      final line = iosLog.last;

      await tester.tap(find.text('${line.seq}'));
      await tester.pump();

      expect(copied, 'job_ios:${line.seq}  ${line.text}');
      expect(find.text('Copied line ${line.seq}'), findsOneWidget);
    });

    testWidgets('opens a failed job at its first error', (tester) async {
      await tester.pumpApp(
        SizedBox(
          height: 200,
          child: LogView(
            steps: failedRun().jobs[1].steps,
            lines: failedLog,
            title: 'Build prod for ios',
            status: XpStatus.jobFailed,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(text('*** Error: Error exporting the archive.'), findsOneWidget);
    });

    testWidgets('opens and closes a step', (tester) async {
      await pumpLog(tester);
      await tester.tap(find.text('Check out'));
      await tester.pump();
      expect(text('Checking out 9a3bc0d'), findsOneWidget);
      await tester.tap(find.text('Build iOS'));
      await tester.pump();
      expect(text('Running pod install...'), findsNothing);
    });

    testWidgets('filters the lines', (tester) async {
      await pumpLog(tester);
      await tester.enterText(find.byType(TextField), 'head');
      await tester.pump();
      expect(text('HEAD is now at 9a3bc0d'), findsOneWidget);
      expect(text('Running pod install...'), findsNothing);
      expect(find.text('Bump version'), findsNothing);
    });

    testWidgets('⌘G and ⇧⌘G go from match to match of the filter', (
      tester,
    ) async {
      await pumpLog(tester);
      expect(runCommand(XpCommand.findNext), isTrue, reason: 'no filter yet');

      await tester.enterText(find.byType(TextField), 'pod');
      await tester.pump();
      for (final command in [
        XpCommand.findNext,
        XpCommand.findNext,
        XpCommand.findPrevious,
      ]) {
        runCommand(command);
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField), 'nothing like it');
      await tester.pump();
      runCommand(XpCommand.findNext);
      await tester.pump();

      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('toggles timestamps, wrap and follow', (tester) async {
      await pumpLog(tester);
      await tester.tap(find.byTooltip('Timestamps  ⇧⌘T'));
      await tester.pump();
      expect(find.text('14:03:09'), findsNothing);
      await tester.tap(find.byTooltip('Wrap lines  ⌥Z'));
      await tester.pump();
      await tester.tap(find.text('Follow'));
      await tester.pump();
      await tester.tap(find.text('Follow'));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      for (final (key, modifiers) in [
        (
          LogicalKeyboardKey.keyT,
          [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft],
        ),
        (LogicalKeyboardKey.keyZ, [LogicalKeyboardKey.altLeft]),
        (LogicalKeyboardKey.arrowDown, [LogicalKeyboardKey.metaLeft]),
        (LogicalKeyboardKey.keyF, [LogicalKeyboardKey.metaLeft]),
        (LogicalKeyboardKey.keyE, [LogicalKeyboardKey.metaLeft]),
      ]) {
        for (final modifier in modifiers) {
          await tester.sendKeyDownEvent(modifier);
        }
        await tester.sendKeyEvent(key);
        for (final modifier in modifiers.reversed) {
          await tester.sendKeyUpEvent(modifier);
        }
        await tester.pump();
      }
      expect(find.text('14:03:09'), findsOneWidget);
    });

    testWidgets('stops following when scrolled back, and jumps to the end', (
      tester,
    ) async {
      final many = [
        for (var seq = 1; seq <= 80; seq++) line(seq, 2, 'line $seq'),
      ];
      await pumpLog(tester, lines: many);
      await tester.pump();
      await tester.pump();
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
      expect(scrollable.position.pixels, greaterThan(0));
      await tester.drag(
        find.text('line 70', findRichText: true),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.pumpApp(
        LogView(
          steps: steps,
          lines: [...many, line(81, 2, 'line 81')],
          title: 'Build prod for ios',
          live: true,
        ),
      );
      await tester.pump();
      expect(
        scrollable.position.pixels,
        lessThan(scrollable.position.maxScrollExtent),
      );
    });

    testWidgets('opens the last step that wrote when none runs', (
      tester,
    ) async {
      await pumpLog(
        tester,
        jobSteps: [
          for (final step in steps)
            JobStep(
              ordinal: step.ordinal,
              kind: step.kind,
              state: StepState.succeeded,
              sideEffect: false,
              attempts: 1,
            ),
        ],
        live: false,
      );
      expect(text('Running pod install...'), findsOneWidget);
    });

    testWidgets('names a step the engine did not describe', (tester) async {
      await pumpLog(tester, jobSteps: const []);
      expect(find.text('Step 1'), findsOneWidget);
    });

    testWidgets('says when there is no output', (tester) async {
      await pumpLog(tester, jobSteps: const [], lines: const []);
      expect(find.text('No output yet'), findsOneWidget);
    });

    testWidgets('scrolls with the mouse wheel', (tester) async {
      await pumpLog(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ListView))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
      await tester.pump();
    });
  });

  group('ansi', () {
    test('splits a line into runs by its SGR sequences', () {
      expect(parseAnsi('plain'), const [AnsiRun('plain')]);
      expect(parseAnsi('\x1B[1;31mred\x1B[0m then'), const [
        AnsiRun('red', foreground: 1, bold: true),
        AnsiRun(' then'),
      ]);
      expect(
        parseAnsi(
          '\x1B[2mdim\x1B[22m\x1B[3mit\x1B[23m\x1B[4mun\x1B[24m'
          '\x1B[7minv\x1B[27m\x1B[92mbg\x1B[39m\x1B[44mb\x1B[49m'
          '\x1B[103mx\x1B[mreset\x1B[5m\x1B[2Kz',
        ),
        const [
          AnsiRun('dim', dim: true),
          AnsiRun('it', italic: true),
          AnsiRun('un', underline: true),
          AnsiRun('inv', inverse: true),
          AnsiRun('bg', foreground: 10),
          AnsiRun('b', background: 4),
          AnsiRun('x', background: 11),
          AnsiRun('reset'),
          AnsiRun('z'),
        ],
      );
    });

    testWidgets('draws runs with the log colours', (tester) async {
      await tester.pumpApp(const SizedBox());
      final colors = tester.element(find.byType(SizedBox)).xpColors;
      final span = ansiSpan(
        const [
          AnsiRun('a', inverse: true),
          AnsiRun('b', background: 1, italic: true, underline: true),
          AnsiRun('c', dim: true),
          AnsiRun('d', foreground: 2, bold: true),
        ],
        const TextStyle(),
        colors,
      );
      final runs = span.children!.cast<TextSpan>();
      expect(runs[0].style!.backgroundColor, colors.logMatch);
      expect(runs[1].style!.fontStyle, FontStyle.italic);
      expect(runs[1].style!.decoration, TextDecoration.underline);
      expect(runs[2].style!.color, colors.logDim);
      expect(runs[3].style!.color, colors.logAnsiGreen);
      expect(runs[3].style!.fontWeight, FontWeight.w600);
      expect(ansiPalette(colors), hasLength(16));
    });
  });
}
