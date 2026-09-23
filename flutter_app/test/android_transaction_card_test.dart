import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/auth/auth_provider.dart';
import 'package:erp/core/db/database_service.dart';
import 'package:erp/modules/stock/ui/transactions_screen.dart';
import 'package:erp/shared/ui/theme/app_theme.dart';

import 'repositories/test_database.dart';

/// A movement on an Android phone is a card, and how tall that card is
/// decides how much of the day's activity fits on one screen. It was 269
/// logical pixels with all eight detail fields, which left barely one
/// card visible; the trimmed, denser card is about 154.
///
/// The ceiling below is what keeps that from creeping back: a field
/// added to the Android card, or the dense flag dropped, pushes straight
/// through it.
const double _cardHeightCeiling = 180;

/// Taller than a real phone on purpose. The list is lazy and sits below
/// the summary and filters, so on a 740px viewport no card is built at
/// all and there is nothing to measure. Card height does not depend on
/// how tall the viewport is.
const Size _tallPhone = Size(360, 1600);

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

  Future<Size> cardSize(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = _tallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TransactionsScreen()),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();

    // 'Produit Un' is the fixture designation, and the designation is the
    // card's headline, so its enclosing InkWell is the card.
    final anchor = find.text('Produit Un');
    expect(anchor, findsWidgets, reason: 'no movement card was built');
    final card = find
        .ancestor(of: anchor.first, matching: find.byType(InkWell))
        .evaluate()
        .first;
    return card.size!;
  }

  testWidgets('a movement card stays short enough to scan a list of them',
      (tester) async {
    final size = await cardSize(tester, TargetPlatform.android);
    expect(
      size.height,
      lessThan(_cardHeightCeiling),
      reason: 'an Android movement card grew back to ${size.height}px',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the Android card drops the fields the wide table keeps',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = _tallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TransactionsScreen()),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();

    // Folded into one signed QUANTITÉ, or dropped as noise on a phone.
    for (final gone in ['PARTENAIRE', 'N° FACTURE', 'ENTRÉE', 'SORTIE']) {
      expect(find.text(gone), findsNothing,
          reason: '$gone should be off the Android card');
    }
    for (final kept in ['DATE', 'QUANTITÉ', 'STOCK APRÈS']) {
      expect(find.text(kept), findsWidgets,
          reason: '$kept should be on the Android card');
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
