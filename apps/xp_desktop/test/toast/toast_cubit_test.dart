import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';

void main() {
  group('ToastCubit', () {
    blocTest<ToastCubit, ToastState>(
      'shows toasts, oldest first, and at most its limit',
      build: ToastCubit.new,
      act: (cubit) => cubit
        ..show('one')
        ..show('two')
        ..show('three')
        ..show('four'),
      skip: 3,
      expect: () => const [
        ToastState([
          Toast(id: 1, message: 'two'),
          Toast(id: 2, message: 'three'),
          Toast(id: 3, message: 'four'),
        ]),
      ],
      verify: (_) => expect(ToastCubit.limit, 3),
    );

    testWidgets('takes a toast away after its time, longer with an action', (
      tester,
    ) async {
      final cubit = ToastCubit()
        ..show('Saved')
        ..show('Removed', action: 'Undo', onAction: () {});

      final [saved, removed] = cubit.state.toasts;
      expect(removed.duration, greaterThan(saved.duration));
      await tester.pump(saved.duration);
      expect(cubit.state.toasts.map((t) => t.message), ['Removed']);
      await tester.pump(removed.duration - saved.duration);
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

    test('an action comes with what it does', () async {
      final cubit = ToastCubit();
      expect(() => cubit.show('Saved', action: 'Undo'), throwsAssertionError);
      expect(() => cubit.show('Saved', onAction: () {}), throwsAssertionError);
      await cubit.close();
    });

    test('takes away the toasts of an owner, and only those', () async {
      final cubit = ToastCubit();
      final page = Object();
      cubit
        ..show('Removed job', action: 'Undo', onAction: () {}, owner: page)
        ..show('Saved')
        ..show('Removed step', action: 'Undo', onAction: () {}, owner: page)
        ..dismissOf(page);

      expect(cubit.state.toasts.map((t) => t.message), ['Saved']);
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
