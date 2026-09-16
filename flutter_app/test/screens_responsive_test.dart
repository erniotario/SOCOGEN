import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/auth/auth_provider.dart';
import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/modules/parametres/ui/company_setup_screen.dart';
import 'package:socogen/modules/rapports/ui/dashboard_screen.dart';
import 'package:socogen/modules/stock/ui/entries_screen.dart';
import 'package:socogen/modules/stock/ui/inventory_screen.dart';
import 'package:socogen/modules/stock/ui/outputs_screen.dart';
import 'package:socogen/modules/catalogue/ui/products_screen.dart';
import 'package:socogen/modules/rapports/ui/reports_screen.dart';
import 'package:socogen/modules/utilisateurs/ui/security_screen.dart';
import 'package:socogen/modules/parametres/ui/settings_screen.dart';
import 'package:socogen/modules/stock/ui/stores_screen.dart';
import 'package:socogen/modules/stock/ui/transactions_screen.dart';
import 'package:socogen/shared/ui/theme/app_theme.dart';

import 'repositories/test_database.dart';

/// Drives every real screen, backed by the shared fixture database, at
/// the window sizes the app actually ships to.
///
/// The component-level checks live in responsive_layout_test.dart; this
/// file is the end-to-end counterpart — it catches a screen that lays
/// out fine in isolation but overflows once its page header, filter bar
/// and table are stacked together inside a real window.
const _sizes = <String, Size>{
  'phone portrait': Size(360, 740),
  'phone landscape': Size(740, 360),
  'tablet': Size(800, 1000),
  'desktop': Size(1280, 800),
};

final _screens = <String, Widget Function()>{
  // Only ever seen on a brand-new install, so it never reaches the
  // other screens' fixture data -- but it is a long French form and
  // belongs in the overflow matrix like the rest.
  'Configuration initiale': () => CompanySetupScreen(onDone: () {}),
  'Tableau de bord': () => const DashboardScreen(),
  'Produits': () => const ProductsScreen(),
  'Entrées': () => const EntriesScreen(),
  'Sorties': () => const OutputsScreen(),
  'Transactions': () => const TransactionsScreen(),
  'Inventaire': () => const InventoryScreen(),
  'Rapports': () => const ReportsScreen(),
  'Magasins': () => const StoresScreen(),
  'Sécurité': () => const SecurityScreen(),
  'Paramètres': () => const SettingsScreen(),
  // NavShell is deliberately absent: it mounts all seven data screens at
  // once, and the test binding then fails teardown with "a Timer is still
  // pending" from their in-flight sqflite queries -- a harness limit, not
  // a layout fault (the app's only Timers are the three search debounces,
  // each cancelled in dispose). Its chrome is Flutter's own NavigationBar
  // and NavigationRail plus a plain sidebar Column, and the sidebar path
  // has been checked visually against the running app.
};

Future<void> _pumpScreen(
  WidgetTester tester,
  Size size,
  Widget screen,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: screen),
      ),
    ),
  );

  // Deliberately not pumpAndSettle: the skeleton placeholders animate on
  // an endless repeat, so settling would never complete while a screen is
  // still loading. Pumping a fixed budget lets the repositories resolve
  // and the real content replace the skeletons.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }

  // Let real async work (the sqflite queries behind each screen) finish
  // before teardown; NavShell mounts seven data screens at once, and the
  // binding fails the test if any of their work is still in flight.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pump();
}

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openTestDatabase();
    DatabaseService.instance.databaseForTesting = db;
  });

  tearDown(() async {
    DatabaseService.instance.databaseForTesting = null;
    await db.close();
  });

  for (final entry in _screens.entries) {
    group(entry.key, () {
      _sizes.forEach((sizeName, size) {
        testWidgets('lays out without overflow on $sizeName', (tester) async {
          await _pumpScreen(tester, size, entry.value());

          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} overflowed at $sizeName ($size)',
          );
        });
      });
    });
  }

  // The Rapports anomaly banner only exists while the ledger holds a
  // balance below zero, so the fixture above -- which has none -- never
  // lays it out. It is a long French sentence beside a button, the exact
  // shape that has overflowed a 360px phone in this project before, so
  // it gets a pass of its own with a negative row seeded first.
  group('Rapports with a negative balance', () {
    _sizes.forEach((sizeName, size) {
      testWidgets('raises the banner without overflow on $sizeName',
          (tester) async {
        // Drives REF2/StoreA from 5 down to -4. The write has to go
        // through runAsync: a testWidgets body runs in a fake-async
        // zone, where a real sqflite future never completes and the
        // test simply hangs.
        await tester.runAsync(() async {
          await db.insert('stock_outputs', {
            'date': '2026-03-02',
            'reference': 'REF2',
            'designation': 'Produit Deux',
            'invoice_number': 'INV4',
            'store_id': 1,
            'destination': 'Client Z',
            'quantity': 9,
          });
        });

        await _pumpScreen(tester, size, const ReportsScreen());

        expect(
          tester.takeException(),
          isNull,
          reason: 'the anomaly banner overflowed at $sizeName ($size)',
        );
        expect(
          find.textContaining('de stock en négatif'),
          findsOneWidget,
          reason: 'the banner should be raised at $sizeName ($size)',
        );
      });
    });
  });
}
