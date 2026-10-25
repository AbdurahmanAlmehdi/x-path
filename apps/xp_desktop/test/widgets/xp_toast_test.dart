import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows the toasts bottom right, with their action', (
    tester,
  ) async {
    final toasts = ToastCubit();
    var undone = false;
    await tester.pumpApp(const Center(child: Text('page')), toasts: toasts);

    toasts
      ..show('Saved')
      ..show(
        'Removed step guard',
        action: 'Undo',
        onAction: () => undone = true,
      );
    await tester.pump();

    expect(find.text('page'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    final removed = tester.getBottomRight(find.byType(XpToast).last);
    final screen = tester.getSize(find.byType(XpToastHost));
    expect(removed.dx, screen.width - 16);
    expect(removed.dy, screen.height - 16);

    await tester.tap(find.widgetWithText(XpButton, 'Undo'));
    await tester.pump();
    expect(undone, isTrue);
    expect(find.text('Removed step guard'), findsNothing);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.byType(XpToast), findsNothing);
  });

  testWidgets('a toast goes away by itself', (tester) async {
    final toasts = ToastCubit();
    await tester.pumpApp(const SizedBox(), toasts: toasts);

    toasts.show('Saved');
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(toasts.state.toasts.single.duration);
    expect(find.text('Saved'), findsNothing);
    expect(context(tester).read<ToastCubit>(), toasts);
  });
}

BuildContext context(WidgetTester tester) =>
    tester.element(find.byType(XpToastHost));
