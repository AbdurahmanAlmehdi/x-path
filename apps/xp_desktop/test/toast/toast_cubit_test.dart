import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';

void main() {
  group('ToastCubit', () {
    blocTest<ToastCubit, ToastState>(
      'shows toasts, oldest first, and at most its limit',
      build: () => ToastCubit(limit: 2),
      act: (cubit) => cubit
        ..show('one')
        ..show('two')
        ..show('three'),
      expect: () => const [
        ToastState([Toast(id: 0, message: 'one')]),
        ToastState([
          Toast(id: 0, message: 'one'),
          Toast(id: 1, message: 'two'),
        ]),
        ToastState([
          Toast(id: 1, message: 'two'),
          Toast(id: 2, message: 'three'),
        ]),
      ],
    );

    testWidgets('takes a toast away after its time, longer with an action', (
      tester,
    ) async {
      final cubit = ToastCubit()
        ..show('Saved')
        ..show('Removed', action: 'Undo', onAction: () {});

      await tester.pump(toastShort);
      expect(cubit.state.toasts.map((t) => t.message), ['Removed']);
      await tester.pump(toastLong - toastShort);
      expect(cubit.state.toasts, isEmpty);
      await cubit.close();
    });

    test('does what a toast offers, once, and takes it away', () async {
      var undone = 0;
      final cubit = ToastCubit();
      final id = cubit.show(
        'Removed',
        action: 'Undo',
        onAction: () => undone++,
      );

      cubit
        ..act(id)
        ..act(id);

      expect(undone, 1);
      expect(cubit.state.toasts, isEmpty);
      await cubit.close();
    });

    test('offers no action without one to do', () async {
      final cubit = ToastCubit()..show('Saved', action: 'Undo');

      expect(cubit.state.toasts.single.action, isNull);
      expect(cubit.state.toasts.single.duration, toastShort);
      await cubit.close();
    });

    test('dismisses a toast, and nothing once closed', () async {
      final cubit = ToastCubit();
      final id = cubit.show('Saved');

      cubit.dismiss(id);
      expect(cubit.state.toasts, isEmpty);
      final late = cubit.show('Late');
      await cubit.close();
      cubit.dismiss(late);
    });
  });
}
