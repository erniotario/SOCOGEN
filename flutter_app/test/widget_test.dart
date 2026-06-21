import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/main.dart';

void main() {
  testWidgets('App boots and shows SOCOGEN title', (WidgetTester tester) async {
    await tester.pumpWidget(const SocogenApp());

    expect(find.text('SOCOGEN'), findsOneWidget);
  });
}
