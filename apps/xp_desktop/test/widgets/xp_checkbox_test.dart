import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('toggles with a click, Space and Return', (tester) async {
    final values = <bool>[];
    await tester.pumpApp(
      XpCheckbox(
        label: 'Keep running',
        detail: 'In the menu bar',
        value: false,
        onChanged: values.add,
      ),
    );

    await tester.tap(find.text('Keep running'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(values, [true, true, true]);
    expect(find.text('In the menu bar'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(XpCheckbox)),
      isSemantics(
        label: 'Keep running',
        hasCheckedState: true,
        isChecked: false,
        isEnabled: true,
      ),
    );
  });

  testWidgets('shows a check when on and does nothing when disabled', (
    tester,
  ) async {
    await tester.pumpApp(
      const XpCheckbox(label: 'Off', value: true, onChanged: null),
    );

    await tester.tap(find.text('Off'));
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });
}
