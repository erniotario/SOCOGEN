import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/db/schema.dart';
import 'package:socogen/data/repositories/settings_repository.dart';
import 'package:socogen/data/repositories/store_repository.dart';
import 'package:socogen/screens/company_setup_screen.dart';
import 'package:socogen/theme/app_theme.dart';

/// First-run setup exists so a new business does not open the app to
/// another company's name and another company's warehouses.
///
/// The load-bearing rule is the one about *existing* installations: they
/// carry no flag, and must never be dragged back through setup.
Future<Database> _openEmptyDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      singleInstance: false,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
      },
    ),
  );
}

void main() {
  late Database db;
  late SettingsRepository settings;
  late StoreRepository stores;

  setUp(() async {
    db = await _openEmptyDb();
    settings = SettingsRepository(database: db);
    stores = StoreRepository(database: db);
  });

  tearDown(() async => db.close());

  group('whether setup is still owed', () {
    test('a brand-new database has not been configured', () async {
      expect(await settings.isCompanyConfigured(), isFalse);
    });

    test('the answer persists once given', () async {
      await settings.markCompanyConfigured();
      expect(await settings.isCompanyConfigured(), isTrue);
    });

    test('an installation already holding a catalogue is left alone', () async {
      // The existing customer: no flag, because the flag did not exist
      // when their database was created. Sending them through setup
      // would be a regression on a working install.
      await db.insert('products', {
        'reference': 'RIZ25',
        'designation': 'RIZ 25KG',
        'unit': 'sac',
      });

      expect(await settings.isCompanyConfigured(), isTrue);
    });

    test('an installation holding only movements is also left alone', () async {
      await db.insert('stores', {'id': 1, 'name': 'Dépôt'});
      await db.insert('stock_entries', {
        'date': '2026-01-05',
        'supplier': 'Fournisseur',
        'reference': 'RIZ25',
        'designation': 'RIZ 25KG',
        'store_id': 1,
        'quantity': 10,
      });

      expect(await settings.isCompanyConfigured(), isTrue);
    });

    test('the backfilled answer is written down, not recomputed', () async {
      await db.insert('products', {
        'reference': 'RIZ25',
        'designation': 'RIZ 25KG',
        'unit': 'sac',
      });
      await settings.isCompanyConfigured();

      // Deleting the catalogue afterwards must not reopen the question:
      // an emptied shop is still a configured installation.
      await db.delete('products');
      expect(await settings.isCompanyConfigured(), isTrue);
    });
  });

  group('the screen', () {
    Future<void> pumpSetup(WidgetTester tester, {VoidCallback? onDone}) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: CompanySetupScreen(
            onDone: onDone ?? () {},
            settingsRepository: settings,
            storeRepository: stores,
          ),
        ),
      );
      await tester.pump();
    }

    /// Lets the real sqflite writes behind a tap finish.
    Future<void> drain(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    testWidgets('no warehouse is suggested, because none is ours to suggest',
        (tester) async {
      await pumpSetup(tester);

      for (final seeded in ['Hysacam', 'Ekie', 'Elig-Essono']) {
        expect(
          find.text(seeded),
          findsNothing,
          reason: 'the first customer must not appear in the next one\'s setup',
        );
      }
    });

    testWidgets('names the business and creates its magasins', (tester) async {
      var done = false;
      await pumpSetup(tester, onDone: () => done = true);

      await tester.enterText(
        find.widgetWithText(TextField, "Nom de l'entreprise *"),
        'ETS KAMGA & FILS',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Ville'),
        'Douala, Cameroun',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Magasin 1'),
        'Dépôt central',
      );

      await tester.tap(find.text('Ajouter un magasin'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Magasin 2'),
        'Boutique Akwa',
      );

      await tester.tap(find.text('Enregistrer et commencer'));
      await drain(tester);

      final saved = await tester.runAsync(() => settings.getSettings());
      expect(saved!.name, 'ETS KAMGA & FILS');
      expect(saved.city, 'Douala, Cameroun');

      // getAllStores orders by name, so compare as a set rather than
      // pinning an order the repository never promised.
      final created = await tester.runAsync(() => stores.getAllStores());
      expect(
        created!.map((s) => s.name).toSet(),
        {'Dépôt central', 'Boutique Akwa'},
      );

      expect(await tester.runAsync(() => settings.isCompanyConfigured()), isTrue);
      expect(done, isTrue);
    });

    testWidgets('refuses to continue without a company name', (tester) async {
      var done = false;
      await pumpSetup(tester, onDone: () => done = true);

      await tester.enterText(
        find.widgetWithText(TextField, 'Magasin 1'),
        'Dépôt central',
      );
      await tester.tap(find.text('Enregistrer et commencer'));
      await drain(tester);

      expect(find.textContaining("nom de l'entreprise"), findsOneWidget);
      expect(done, isFalse);
      expect(await tester.runAsync(() => stores.getAllStores()), isEmpty);
    });

    testWidgets('refuses to continue without a magasin', (tester) async {
      await pumpSetup(tester);

      await tester.enterText(
        find.widgetWithText(TextField, "Nom de l'entreprise *"),
        'ETS KAMGA & FILS',
      );
      await tester.tap(find.text('Enregistrer et commencer'));
      await drain(tester);

      expect(find.textContaining('au moins un magasin'), findsOneWidget);
      expect(
        await tester.runAsync(() => settings.isCompanyConfigured()),
        isFalse,
        reason: 'a refused form must not count as an answer',
      );
    });

    testWidgets('refuses two magasins with the same name', (tester) async {
      await pumpSetup(tester);

      await tester.enterText(
        find.widgetWithText(TextField, "Nom de l'entreprise *"),
        'ETS KAMGA & FILS',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Magasin 1'),
        'Dépôt',
      );
      await tester.tap(find.text('Ajouter un magasin'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Magasin 2'),
        'dépôt',
      );

      await tester.tap(find.text('Enregistrer et commencer'));
      await drain(tester);

      expect(find.textContaining('même nom'), findsOneWidget);
      expect(await tester.runAsync(() => stores.getAllStores()), isEmpty);
    });

    testWidgets('a device joining by sync creates nothing', (tester) async {
      var done = false;
      await pumpSetup(tester, onDone: () => done = true);

      await tester.tap(
        find.text('Je vais synchroniser avec un autre appareil'),
      );
      await drain(tester);

      // Inventing magasins here would duplicate the first device's on the
      // next merge, which matches stores by name.
      expect(await tester.runAsync(() => stores.getAllStores()), isEmpty);
      expect(await tester.runAsync(() => settings.isCompanyConfigured()), isTrue,
          reason: 'the question was answered, so it must not return');
      expect(done, isTrue);
    });
  });
}
