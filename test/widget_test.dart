import 'package:flutter_test/flutter_test.dart';
import 'package:neko/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NekoApp());
    expect(find.text('NEKO'), findsOneWidget);
  });
}
