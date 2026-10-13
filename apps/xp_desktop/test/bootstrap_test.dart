import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/bootstrap.dart';

class _TestCubit extends Cubit<int> {
  new() : super(0);
}

void main() {
  group('AppBlocObserver', () {
    test('logs changes and errors without throwing', () {
      const observer = AppBlocObserver();
      final cubit = _TestCubit();
      addTearDown(cubit.close);

      expect(
        () => observer
          ..onChange(cubit, const Change(currentState: 0, nextState: 1))
          ..onError(cubit, Exception('oops'), StackTrace.current),
        returnsNormally,
      );
    });
  });

  group('bootstrap', () {
    testWidgets('installs the observer and runs the built widget', (
      tester,
    ) async {
      final onError = FlutterError.onError;
      final observer = Bloc.observer;
      addTearDown(() {
        FlutterError.onError = onError;
        Bloc.observer = observer;
      });

      await bootstrap(() => const SizedBox(key: Key('built')));

      expect(Bloc.observer, isA<AppBlocObserver>());
      expect(find.byKey(const Key('built')), findsOneWidget);
      expect(
        () => FlutterError.onError!(
          FlutterErrorDetails(exception: Exception('oops')),
        ),
        returnsNormally,
      );
    });
  });
}
