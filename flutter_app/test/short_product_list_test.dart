import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/auth/auth_provider.dart';
import 'package:socogen/data/db/database_service.dart';
import 'package:socogen/screens/dashboard_screen.dart';
import 'package:socogen/screens/reports_screen.dart';
import 'package:socogen/theme/app_theme.dart';

import 'repositories/test_database.dart';

/// The Accueil and Rapport product lists are cut to three columns on
/// Android and keep the full breakdown everywhere else, so both halves
/// of that rule are worth holding still.

/// Columns only the full list carries.
const _fullOnly = [
  'RÉFÉRENCE',
  'UNITÉ',
  'STOCK INITIAL',
  'ENTRÉES',
  'SORTIES',
];

/// The three that survive on Android. MAGASIN is new to the Accueil
/// here -- off Android that list aggregates a product across stores and
/// has never named one.
const _shortColumns = ['DÉSIGNATION', 'MAGASIN', 'STOCK ACTUEL'];

/// What the desktop lists must still carry, on both screens.
const _fullExpected = ['DÉSIGNATION', 'STOCK ACTUEL', ..._fullOnly];

Future<void> _pump(WidgetTester tester, Widget screen) async {
  // Wide enough for the table rather than the card layout, so the column
  // headings are on screen to assert against.
  tester.view.physicalSize = const Size(1280, 800);
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
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
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
    debugDefaultTargetPlatformOverride = null;
    DatabaseService.instance.databaseForTesting = null;
    await db.close();
  });

  for (final screen in <String, Widget Function()>{
    'Accueil': () => const DashboardScreen(),
    'Rapport': () => const ReportsScreen(),
  }.entries) {
    group(screen.key, () {
      testWidgets('shows only product, magasin and stock on Android',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await _pump(tester, screen.value());

        for (final label in _shortColumns) {
          expect(find.text(label), findsOneWidget,
              reason: '$label should be on the Android list');
        }
        for (final label in _fullOnly) {
          expect(find.text(label), findsNothing,
              reason: '$label should be off the Android list');
        }
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('keeps the full breakdown off Android', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        await _pump(tester, screen.value());

        for (final label in _fullExpected) {
          expect(find.text(label), findsOneWidget,
              reason: '$label should be on the desktop list');
        }
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}
