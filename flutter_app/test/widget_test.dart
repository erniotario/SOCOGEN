import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/main.dart';
import 'package:socogen/theme/app_branding.dart';

void main() {
  testWidgets('App boots and shows the product name', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());

    expect(find.text(AppBranding.productName), findsOneWidget);
  });

  test('the product no longer carries its first customer\'s name', () {
    // The app was named after SOCOGEN, who are now one customer among
    // however many install it. Their name is data -- company_settings,
    // filled in at first run -- not the name of the software.
    expect(AppBranding.productName, 'SM');
    expect(AppBranding.windowTitle, contains('SM'));
    expect(AppBranding.windowTitle, isNot(contains('SOCOGEN')));
  });
}
