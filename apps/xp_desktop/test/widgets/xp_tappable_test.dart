import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('XpTappable takes the focus and acts on Return and Space', (
    tester,
  ) async {
    var taps = 0;
    final hovers = <bool>[];
    Offset? secondary;
    await tester.pumpApp(
      Center(
        child: XpTappable(
          label: 'Row',
          onTap: () => taps++,
          onHover: hovers.add,
          onSecondaryTap: (position) => secondary = position,
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(find.byType(XpTappable));
    await tester.tapAt(
      tester.getCenter(find.byType(XpTappable)),
      buttons: kSecondaryButton,
    );
    await tester.pump();

    expect(taps, 3);
    expect(secondary, tester.getCenter(find.byType(XpTappable)));
    expect(
      tester.getSemantics(find.byType(XpTappable)),
      isSemantics(label: 'Row', isButton: true),
    );
  });

  testWidgets('XpTappable without onTap is inert', (tester) async {
    await tester.pumpApp(const XpTappable(onTap: null, child: Text('Row')));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester.getSemantics(find.byType(XpTappable)),
      isSemantics(isButton: true, isEnabled: false),
    );
  });

  testWidgets('a context menu copies, acts, and marks what destroys', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
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
    final done = <String>[];
    await tester.pumpApp(
      Center(
        child: XpMenuButton(
          label: 'More',
          actions: [
            const XpMenuAction.copy('Copy commit', '9a3bc0d'),
            XpMenuAction('Delete', () => done.add('delete'), destructive: true),
          ],
        ),
      ),
    );

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy commit'));
    await tester.pumpAndSettle();
    expect(copied, ['9a3bc0d']);
    expect(find.text('Copied 9a3bc0d'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(done, ['delete']);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(done, ['delete'], reason: 'closing the menu does nothing');
  });

  testWidgets('a disabled menu button opens nothing', (tester) async {
    await tester.pumpApp(
      const Center(child: XpMenuButton(label: 'More', actions: null)),
    );

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<XpMenuAction>), findsNothing);
  });

  testWidgets('a busy button keeps the focus', (tester) async {
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    await tester.pumpApp(
      ValueListenableBuilder(
        valueListenable: busy,
        builder: (_, value, _) =>
            XpButton(label: 'Save', busy: value, onPressed: () {}),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    busy.value = true;
    await tester.pump();

    expect(
      find.ancestor(
        of: find.byElementPredicate(
          (element) =>
              identical(element, FocusManager.instance.primaryFocus?.context),
        ),
        matching: find.byType(XpButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a status icon says its status', (tester) async {
    await tester.pumpApp(const XpStatusIcon(XpStatus.jobQueued));

    expect(find.bySemanticsLabel('Queued'), findsOneWidget);
  });
}
