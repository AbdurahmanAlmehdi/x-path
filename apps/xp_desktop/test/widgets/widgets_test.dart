import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/pump_app.dart';

void main() {
  group('XpButton', () {
    testWidgets('runs on tap, hover, press and keyboard; shows its hint', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpApp(
        Column(
          children: [
            for (final kind in XpButtonKind.values)
              XpButton(
                label: kind.name,
                kind: kind,
                hint: '⌘N',
                icon: PhosphorIconsRegular.plus,
                onPressed: () => presses++,
              ),
            XpButton(
              label: 'small',
              size: XpButtonSize.small,
              icon: PhosphorIconsRegular.plus,
              onPressed: () {},
            ),
            XpButton(
              label: 'large',
              size: XpButtonSize.large,
              onPressed: () {},
            ),
          ],
        ),
      );
      expect(find.text('⌘N'), findsNWidgets(XpButtonKind.values.length));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('primary')));
      await tester.pump();
      await gesture.down(tester.getCenter(find.text('primary')));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(presses, 1);

      await tester.tap(find.text('warning'));
      await tester.pump();
      expect(presses, 2);

      // A press that slides off does not count.
      final slide = await tester.startGesture(
        tester.getCenter(find.text('secondary')),
      );
      await tester.pump();
      await slide.moveBy(const Offset(0, 300));
      await slide.cancel();
      await tester.pump();
      expect(presses, 2);

      // The keyboard: focus with Tab, activate with Space.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(presses, 3);
    });

    testWidgets('a disabled or busy button does nothing; a tooltip says why', (
      tester,
    ) async {
      await tester.pumpApp(
        const Column(
          children: [
            XpButton(label: 'off', onPressed: null, tooltip: 'Read-only'),
            XpButton(
              label: 'tertiary off',
              kind: XpButtonKind.tertiary,
              onPressed: null,
            ),
            XpButton(label: 'busy', onPressed: _never, busy: true),
          ],
        ),
      );
      await tester.tap(find.text('off'));
      await tester.tap(find.text('busy'));
      await tester.pump();
      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.byType(XpSpinner), findsOneWidget);
    });
  });

  group('status', () {
    testWidgets('icons spin, turn or stand still; labels and badges', (
      tester,
    ) async {
      await tester.pumpApp(
        const Column(
          children: [
            XpStatusIcon(XpStatus.jobRunning),
            XpStatusIcon(XpStatus.engineReconnecting),
            XpStatusIcon(XpStatus.jobSucceeded),
            XpStatusLabel(XpStatus.scanWarning, 'Warning'),
            XpBadge(XpStatus.engineConnected, 'Showing'),
          ],
        ),
      );
      expect(find.byType(XpSpinner), findsNWidgets(2));
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Showing'), findsOneWidget);
    });

    testWidgets('a spinner turns unless motion is reduced', (tester) async {
      await tester.pumpWidget(
        themed(
          const XpSpinner(
            icon: PhosphorIconsRegular.circleNotch,
            size: 14,
            color: Color(0xFF000000),
          ),
        ),
      );
      final turns = tester.widget<RotationTransition>(
        find.byType(RotationTransition),
      );
      expect(turns.turns.isAnimating, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('layout', () {
    testWidgets('labels, panels, rules, code, headers and messages', (
      tester,
    ) async {
      await tester.pumpApp(
        const Column(
          children: [
            XpSectionLabel('Projects'),
            XpPanel(child: Text('panel')),
            XpHairline(),
            SizedBox(height: 10, child: XpHairline(vertical: true)),
            XpCode('5.4.1 (3283)', size: 13),
            XpPageHeader(
              title: 'Engines',
              subtitle: 'Where XPath runs',
              actions: [Text('action')],
            ),
            XpPageHeader(title: 'Bare'),
            XpMessage(XpStatus.scanError, 'Broken'),
            XpMessage.error('Not saved.'),
          ],
        ),
      );
      expect(find.byIcon(PhosphorIconsRegular.warningCircle), findsOneWidget);
      expect(find.text('PROJECTS'), findsOneWidget);
      for (final text in [
        'panel',
        '5.4.1 (3283)',
        'Engines',
        'action',
        'Broken',
        'Not saved.',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
    });

    testWidgets('an error state retries', (tester) async {
      var retries = 0;
      await tester.pumpApp(
        XpErrorState('Cannot reach the engine.', onRetry: () => retries++),
      );
      expect(find.text('Cannot reach the engine.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('loading bars stand in for what loads', (tester) async {
      await tester.pumpApp(const XpLoading(rows: 4));
      expect(
        find.descendant(
          of: find.byType(XpLoading),
          matching: find.byType(FractionallySizedBox),
        ),
        findsNWidgets(4),
      );
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('a text field with a trailing control', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? changed;
      await tester.pumpApp(
        Column(
          children: [
            XpTextField(
              label: 'Folder',
              controller: controller,
              hint: '/src',
              code: true,
              onChanged: (value) => changed = value,
              trailing: const Text('Choose'),
            ),
            XpTextField(
              label: 'Token',
              controller: TextEditingController(text: 'x'),
              obscure: true,
              enabled: false,
            ),
          ],
        ),
      );
      await tester.enterText(find.byType(TextField).first, '/src/app');
      expect(changed, '/src/app');
      expect(find.text('Choose'), findsOneWidget);
      expect(find.text('FOLDER'), findsOneWidget);
    });

    testWidgets('a select opens its values and picks one', (tester) async {
      String? picked;
      await tester.pumpApp(
        Column(
          children: [
            XpSelect<String>(
              value: 'dev',
              values: const ['dev', 'prod'],
              labelOf: (value) => value,
              onChanged: (value) => picked = value,
              code: true,
            ),
            XpSelect<String>(
              value: 'off',
              values: const ['off'],
              labelOf: (value) => value,
              onChanged: null,
            ),
          ],
        ),
      );
      await tester.tap(find.text('dev'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('prod').last);
      await tester.pumpAndSettle();
      expect(picked, 'prod');
    });
  });
}

void _never() {
  group('XpConfirmDialog', () {
    testWidgets('says what happens and answers with the button pressed', (
      tester,
    ) async {
      final answers = <bool>[];
      await tester.pumpApp(
        Builder(
          builder: (context) => XpButton(
            label: 'Delete',
            onPressed: () async => answers.add(
              await confirmAction(
                context,
                title: 'Delete it?',
                points: const ['It is gone for good.'],
                keep: 'Keep',
                confirm: 'Delete it',
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('Delete it?'), findsOneWidget);
      expect(find.text('•  It is gone for good.'), findsOneWidget);
      // Return does nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(XpConfirmDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await open();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await open();
      await tester.tap(find.text('Delete it'));
      await tester.pumpAndSettle();
      await open();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(answers, [false, false, true, false]);
    });
  });

  group('XpSha', () {
    testWidgets('shows seven characters and copies the whole commit', (
      tester,
    ) async {
      final clipboard = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpApp(const XpSha('9a3bc0d4e5f6'));
      expect(find.text('9a3bc0d'), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        '9a3bc0d4e5f6 · click to copy',
      );
      await tester.tap(find.text('9a3bc0d'));
      await tester.pump();
      expect(clipboard, ['9a3bc0d4e5f6']);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Copied');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        '9a3bc0d4e5f6 · click to copy',
      );
    });
  });

  group('XpTime', () {
    testWidgets('shows the time of day or a date, and the time in full', (
      tester,
    ) async {
      final now = testNow.subtract(const Duration(hours: 2));
      final old = testNow.subtract(const Duration(days: 3));
      await tester.pumpApp(Column(children: [XpTime(now), XpTime(old)]));
      expect(find.text(formatTime(now)), findsOneWidget);
      expect(find.text(formatDateTime(old)), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip).first).message,
        formatAbsolute(now),
      );
    });
  });
}
