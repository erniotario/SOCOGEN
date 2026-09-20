import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/auth/auth_provider.dart';
import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/modules/tiers/ui/tiers_screen.dart';
import 'package:socogen/shared/ui/theme/app_theme.dart';

import 'repositories/test_database.dart';

/// L'écran des fiches clients et fournisseurs.
///
/// Le fixture porte deux fiches : « Fournisseur A » et « Client X ».
/// Les écrans pompent un budget fixe plutôt que `pumpAndSettle` — les
/// squelettes s'animent en boucle et le settle n'aboutirait jamais.
/// `runAsync` laisse les requêtes sqflite se terminer entre deux.
/// Pompe jusqu'à ce que l'écran ait rattrapé, sans `pumpAndSettle`.
///
/// Deux raisons de boucler plutôt que de pomper un budget fixe. Les
/// squelettes s'animent en boucle, donc `pumpAndSettle` n'aboutirait
/// jamais. Et l'écran recharge par `runAsync` : le `Future` qu'il pose
/// dans son `setState` naît dans la vraie boucle d'événements, que le
/// test ne fait pas tourner entre deux `pump`. Il faut donc alterner
/// `runAsync` et `pump` plusieurs fois — un seul tour asserte sur
/// l'affichage d'avant, ce qui fait passer un écran cassé pour bon.
Future<void> _pomperJusqua(
  WidgetTester tester, {
  Finder? apparait,
  Finder? disparait,
  int tours = 6,
}) async {
  bool atteint() {
    if (apparait != null && apparait.evaluate().isEmpty) return false;
    if (disparait != null && disparait.evaluate().isNotEmpty) return false;
    return true;
  }

  for (var tour = 0; tour < tours; tour++) {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    if (atteint()) return;
  }
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

  Future<void> pomper(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TiersScreen()),
        ),
      ),
    );
    await _pomperJusqua(tester, apparait: find.text('Client X'));
  }


  testWidgets('la liste montre les fiches', (tester) async {
    await pomper(tester);

    expect(find.text('Fournisseur A'), findsOneWidget);
    expect(find.text('Client X'), findsOneWidget);
  });

  testWidgets('la recherche filtre la liste', (tester) async {
    await pomper(tester);

    await tester.enterText(find.byType(TextField).first, 'Client');
    // Les deux conditions : sans « apparaît », la boucle s'arrêterait
    // pendant le squelette, où plus rien n'est affiché.
    await _pomperJusqua(
      tester,
      apparait: find.text('Client X'),
      disparait: find.text('Fournisseur A'),
    );

    expect(find.text('Client X'), findsOneWidget);
    expect(find.text('Fournisseur A'), findsNothing);
  });
}
