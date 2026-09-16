import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/auth/auth_provider.dart';
import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/modules/stock/repositories/stock_repository.dart';
import 'package:socogen/modules/stock/ui/inventory_screen.dart';
import 'package:socogen/shared/ui/theme/app_theme.dart';

import 'repositories/test_database.dart';

/// Drives the real Inventaire screen end to end: pick an article, type
/// what the shelf holds, add it to the count, validate.
///
/// The fixture opens with REF1/StoreA at 18.
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

  /// Pumps a fixed budget, then lets the real sqflite futures behind the
  /// screen resolve. Settling is not an option: the skeleton placeholders
  /// animate on an endless repeat.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  Future<void> pumpScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: InventoryScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  /// Counts REF1 in the magasin the form defaults to (StoreA).
  Future<void> countRef1(WidgetTester tester, int counted) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Article *'),
      'REF1',
    );
    await settle(tester);

    await tester.tap(find.text('REF1 — Produit Un').last);
    await settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Quantité comptée *'),
      '$counted',
    );
    await settle(tester);

    await tester.tap(find.text('Ajouter au comptage'));
    await settle(tester);
  }

  testWidgets('an empty screen says what to do, and counts nothing', (tester) async {
    await pumpScreen(tester, const Size(1280, 800));

    expect(find.text('Aucun article compté'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('counting an article shows it with its écart', (tester) async {
    await pumpScreen(tester, const Size(1280, 800));

    // The shelf holds 25 where the ledger says 18.
    await countRef1(tester, 25);

    // defaultTargetPlatform is android under `flutter test`, so the
    // table shows the cut-back Android column set: designation, counted,
    // écart. The reference column is asserted separately below.
    expect(find.text('Produit Un'), findsWidgets);
    expect(find.text('+7'), findsWidgets, reason: '25 comptés - 18 au registre');
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing is written until the count is validated', (tester) async {
    await pumpScreen(tester, const Size(1280, 800));
    await countRef1(tester, 25);

    final stock = StockRepository(database: db);
    final balance = await tester.runAsync(
      () => stock.balanceExcluding(reference: 'REF1', storeId: 1),
    );

    expect(balance, 18, reason: 'un comptage est un brouillon jusqu\'à validation');
  });

  testWidgets('validating posts the adjustment and clears the draft', (tester) async {
    await pumpScreen(tester, const Size(1280, 800));
    await countRef1(tester, 25);

    await tester.tap(find.text('Valider l\'inventaire'));
    await settle(tester);

    // Confirm the dialog.
    expect(find.text('Valider'), findsOneWidget);
    await tester.tap(find.text('Valider'));
    await settle(tester);

    final stock = StockRepository(database: db);
    final balance = await tester.runAsync(
      () => stock.balanceExcluding(reference: 'REF1', storeId: 1),
    );
    expect(balance, 25, reason: 'le stock suit le comptage');

    final adjustments = await tester.runAsync(
      () => db.query('stock_entries',
          where: 'supplier = ?', whereArgs: ['Inventaire physique']),
    );
    expect(adjustments, hasLength(1));

    // Validating reloads the catalogue, so the screen is briefly back on
    // its skeleton; let that land before asserting on what it shows.
    await settle(tester);
    expect(find.text('Aucun article compté'), findsOneWidget,
        reason: 'le brouillon est vidé après validation');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the desk layout carries the reference and the théorique',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpScreen(tester, const Size(1280, 800));
    await countRef1(tester, 25);

    expect(find.text('REF1'), findsWidgets);
    expect(find.text('18'), findsWidgets, reason: 'le stock théorique');
    expect(tester.takeException(), isNull);

    // Reset inside the body: the framework checks the foundation debug
    // variables before tearDown runs.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a populated count lays out on a phone without overflow', (tester) async {
    await pumpScreen(tester, const Size(360, 740));
    await countRef1(tester, 25);

    // The summary card's tallies and both buttons are on screen at the
    // narrowest size the app ships to.
    expect(find.text('Valider l\'inventaire'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
