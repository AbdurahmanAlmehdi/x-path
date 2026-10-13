import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/main.dart' as app;

void main() {
  testWidgets('main starts the app', (tester) async {
    final onError = FlutterError.onError;
    final observer = Bloc.observer;
    addTearDown(() {
      FlutterError.onError = onError;
      Bloc.observer = observer;
    });

    await app.main();
    await tester.pump();

    expect(find.text('XPath'), findsOneWidget);
  });
}
