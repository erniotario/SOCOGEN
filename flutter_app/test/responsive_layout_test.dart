import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/theme/app_theme.dart';
import 'package:socogen/widgets/adaptive_table.dart';
import 'package:socogen/widgets/filter_bar.dart';
import 'package:socogen/widgets/kpi_card.dart';
import 'package:socogen/widgets/page_header.dart';
import 'package:socogen/widgets/responsive_row.dart';

/// Window sizes the app has to survive: a phone in portrait, a tablet /
/// small desktop window, and a full desktop window.
const _sizes = <String, Size>{
  'phone portrait': Size(360, 740),
  'phone landscape': Size(740, 360),
  'tablet': Size(800, 1000),
  'desktop': Size(1280, 800),
};

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget child,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// A RenderFlex overflow is reported as a recorded framework exception
/// rather than a thrown error, so assert on it explicitly.
void _expectNoOverflow(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'the layout overflowed at this window size',
  );
}

AdaptiveTable _sampleTable({int rows = 12}) {
  return AdaptiveTable(
    actionsColumn: 6,
    columns: const [
      AppColumn('RÉFÉRENCE', flex: 11),
      AppColumn('DÉSIGNATION', flex: 20),
      AppColumn('UNITÉ', flex: 7),
      AppColumn('MAGASINS', flex: 13),
      AppColumn.number('STOCK INITIAL', flex: 10),
      AppColumn.number('STOCK ACTUEL', flex: 10),
      AppColumn.actions(flex: 11),
    ],
    rows: [
      for (var i = 0; i < rows; i++)
        AppRow(
          cells: [
            Cells.identifier('REF-${i.toString().padLeft(4, '0')}'),
            Cells.text('Désignation de produit assez longue numéro $i'),
            Cells.muted('sac'),
            Cells.muted('Hysacam, Ekie, Elig-Essono'),
            Cells.number(1200 + i),
            Cells.number(340 + i, strong: true),
            const RowActionsStub(),
          ],
        ),
    ],
  );
}

/// Stand-in for the real row actions, so the table test does not depend
/// on icon-button theming.
class RowActionsStub extends StatelessWidget {
  const RowActionsStub({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 64, height: 24);
}

void main() {
  group('AdaptiveTable', () {
    _sizes.forEach((name, size) {
      testWidgets('lays out without overflow on $name', (tester) async {
        await _pumpAt(tester, size, _sampleTable());
        _expectNoOverflow(tester);
      });
    });

    testWidgets('renders record cards on a phone and a header row on '
        'the desktop', (tester) async {
      await _pumpAt(tester, const Size(360, 740), _sampleTable(rows: 3));
      // The card layout repeats the column label next to each value.
      expect(find.text('STOCK ACTUEL'), findsNWidgets(3));

      await _pumpAt(tester, const Size(1280, 800), _sampleTable(rows: 3));
      // The table layout prints each column label exactly once.
      expect(find.text('STOCK ACTUEL'), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no rows',
        (tester) async {
      await _pumpAt(
        tester,
        const Size(360, 740),
        const AdaptiveTable(
          columns: [AppColumn('RÉFÉRENCE'), AppColumn('DÉSIGNATION')],
          rows: [],
          empty: Center(child: Text('Aucun produit')),
        ),
      );
      expect(find.text('Aucun produit'), findsOneWidget);
      _expectNoOverflow(tester);
    });
  });

  group('PageHeader', () {
    _sizes.forEach((name, size) {
      testWidgets('fits its actions on $name', (tester) async {
        await _pumpAt(
          tester,
          size,
          Column(
            children: [
              PageHeader(
                title: 'Transactions',
                subtitle: 'Historique des entrées et sorties',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Rapport PDF (tout)'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('Rapport PDF'),
                  ),
                ],
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        );
        _expectNoOverflow(tester);
      });
    });
  });

  group('KpiRow', () {
    _sizes.forEach((name, size) {
      testWidgets('wraps four tiles without overflow on $name',
          (tester) async {
        await _pumpAt(
          tester,
          size,
          const SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: KpiRow(
              cards: [
                KpiCard(
                  icon: Icons.inventory_2_outlined,
                  label: 'Produits',
                  value: '128',
                  color: Colors.blue,
                ),
                KpiCard(
                  icon: Icons.call_received,
                  label: 'Entrées totales',
                  value: '12 480',
                  color: Colors.green,
                ),
                KpiCard(
                  icon: Icons.call_made,
                  label: 'Sorties totales',
                  value: '9 305',
                  color: Colors.red,
                ),
                KpiCard(
                  icon: Icons.store_outlined,
                  label: 'Magasins',
                  value: '3',
                  color: Colors.orange,
                ),
              ],
            ),
          ),
        );
        _expectNoOverflow(tester);
      });
    });
  });

  group('FilterBar', () {
    _sizes.forEach((name, size) {
      testWidgets('stacks or spreads its fields without overflow on $name',
          (tester) async {
        await _pumpAt(
          tester,
          size,
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: FilterBar(
              onClear: () {},
              fields: [
                FilterField(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Rechercher',
                      hintText: 'Référence, désignation…',
                    ),
                  ),
                ),
                FilterField(
                  flex: 2,
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Magasin'),
                    items: const [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Tous les magasins'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                FilterField(
                  flex: 2,
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      DropdownMenuItem<int?>(value: null, child: Text('Tous')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        );
        _expectNoOverflow(tester);
      });
    });
  });

  group('ResponsiveRow', () {
    testWidgets('stacks its children below the threshold', (tester) async {
      await _pumpAt(
        tester,
        const Size(360, 740),
        const ResponsiveRow(
          items: [
            RowItem(child: SizedBox(height: 40, child: Text('Un'))),
            RowItem(child: SizedBox(height: 40, child: Text('Deux'))),
            RowItem(child: SizedBox(height: 40, child: Text('Trois'))),
          ],
        ),
      );
      _expectNoOverflow(tester);

      // Stacked: each child owns the full width of the row.
      final first = tester.getRect(find.text('Un'));
      final second = tester.getRect(find.text('Deux'));
      expect(second.top, greaterThan(first.top));
    });

    testWidgets('spreads its children above the threshold', (tester) async {
      await _pumpAt(
        tester,
        const Size(1280, 800),
        const ResponsiveRow(
          items: [
            RowItem(child: SizedBox(height: 40, child: Text('Un'))),
            RowItem(child: SizedBox(height: 40, child: Text('Deux'))),
            RowItem(child: SizedBox(height: 40, child: Text('Trois'))),
          ],
        ),
      );
      _expectNoOverflow(tester);

      final first = tester.getRect(find.text('Un'));
      final second = tester.getRect(find.text('Deux'));
      expect(second.top, equals(first.top));
      expect(second.left, greaterThan(first.left));
    });
  });
}
