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
          ],
        ),
      );
      expect(find.text('PROJECTS'), findsOneWidget);
      for (final text in [
        'panel',
        '5.4.1 (3283)',
        'Engines',
        'action',
        'Broken',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
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

void _never() {}
