import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/app/app.dart';

void main() {
  group('App', () {
    testWidgets('renders the app name', (tester) async {
      await tester.pumpWidget(const App());
      expect(find.text('XPath'), findsOneWidget);
    });
  });
}
