import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/theme/app_theme.dart';
import 'package:socogen/widgets/adaptive_table.dart';

/// Guards the fix for stuttering scroll on Rapports/Entrées/Sorties/
/// Transactions.
///
/// Those pages put the table under other content (KPI tiles, a filter
/// bar, an entry form). The obvious way to do that is
/// `AdaptiveTable(shrinkWrap: true)` inside the page's ListView — but
/// shrink-wrapping builds *every* row before the first frame, so a real
/// 660-row catalogue janked. [SliverAdaptiveTable] keeps the single
/// scroll while letting the viewport build only what it shows.
///
/// The assertions below are deliberately behavioural: a row far down the
/// list must not exist in the tree until it is scrolled to.
AdaptiveTable _table(int count) => AdaptiveTable(
      columns: const [
        AppColumn('RÉFÉRENCE'),
        AppColumn('DÉSIGNATION'),
        AppColumn.number('STOCK'),
      ],
      rows: [
        for (var i = 0; i < count; i++)
          AppRow(
            cells: [
              Cells.identifier('REF$i'),
              Cells.text('Produit $i'),
              Cells.number(i),
            ],
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, Size size, int rows) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
            SliverAdaptiveTable(table: _table(rows)),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SliverAdaptiveTable builds rows lazily', () {
    testWidgets('on a desktop-width table', (tester) async {
      await _pump(tester, const Size(1280, 800), 500);

      // The first rows are on screen...
      expect(find.text('REF0'), findsOneWidget);
      // ...and rows far below the fold were never built.
      expect(find.text('REF400'), findsNothing);
      expect(find.text('REF499'), findsNothing);
    });

    testWidgets('on a phone-width card list', (tester) async {
      await _pump(tester, const Size(360, 740), 500);

      expect(find.text('REF0'), findsOneWidget);
      expect(find.text('REF400'), findsNothing);
    });

    testWidgets('a row further down is built once scrolled to',
        (tester) async {
      await _pump(tester, const Size(1280, 800), 500);
      expect(find.text('REF60'), findsNothing);

      await tester.scrollUntilVisible(find.text('REF60'), 300);
      expect(find.text('REF60'), findsOneWidget);
      // ...and the top of the list has now been recycled away.
      expect(find.text('REF0'), findsNothing);
    });
  });
}
