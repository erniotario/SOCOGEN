import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/db/schema.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/modules/catalogue/repositories/product_repository.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/modules/parametres/repositories/settings_repository.dart';
import 'package:socogen/modules/parametres/repositories/tva_repository.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/rapports/repositories/report_repository.dart';
import 'package:socogen/shared/models/view_models.dart';

/// Le seuil d'alerte, désormais propriété de l'article.
///
/// Il valait dix pour tout le catalogue — du riz à la tonne comme d'un
/// carton d'allumettes. Trois règles à tenir : l'article passe avant
/// l'entreprise, « pas de seuil » n'est pas « seuil à zéro », et le
/// badge lu en Dart doit juger comme le compteur calculé en SQL.
Future<Database> _base() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      singleInstance: false,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        for (final sql in AppSchema.createStatements) {
          await d.execute(sql);
        }
      },
    ),
  );
  await db.insert('company_settings', {'id': 1, 'name': 'Test'});
  await db.insert('stores', {'id': 1, 'name': 'Hysacam'});
  return db;
}

void main() {
  late Database db;
  late ProductRepository produits;
  late CatalogueService catalogue;
  late ParametresService parametres;
  late ReportRepository rapports;

  setUp(() async {
    db = await _base();
    produits = ProductRepository(database: db);
    parametres = ParametresService(
      settingsRepository: SettingsRepository(database: db),
      tvaRepository: TvaRepository(database: db),
    );
    catalogue = CatalogueService(
      productRepository: produits,
      parametresService: parametres,
    );
    rapports = ReportRepository(database: db);
  });

  tearDown(() async => db.close());

  /// Un article avec [stock] en magasin, et le seuil qu'on lui donne.
  Future<int> article(String ref, {required int stock, int? seuil}) async {
    final id = await produits.createProduct(
      reference: ref,
      designation: ref,
      unit: 'unité',
      stockMin: seuil,
    );
    await db.insert('product_stocks',
        {'product_id': id, 'store_id': 1, 'initial_stock': stock});
    return id;
  }

  group('le seuil par défaut', () {
    test("vaut dix, ce que le code appliquait en dur", () async {
      expect(await parametres.seuilStockParDefaut(), 10);
    });

    test("s'applique à un article qui n'en déclare pas", () async {
      await article('RIZ', stock: 5);

      final ligne = (await rapports.getReportRows()).single;
      expect(ligne.stockMin, 10);
      expect(ligne.status, StockStatus.stockFaible);
    });

    test('change pour tout le catalogue', () async {
      await article('RIZ', stock: 5);
      await parametres.definirSeuilStockParDefaut(3);

      final ligne = (await rapports.getReportRows()).single;
      expect(ligne.stockMin, 3);
      expect(ligne.status, StockStatus.enStock, reason: '5 ≥ 3');
    });

    test('refuse un négatif', () async {
      await expectLater(
        parametres.definirSeuilStockParDefaut(-1),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group("le seuil d'un article", () {
    test("passe avant celui de l'entreprise", () async {
      // Le cas qui a motivé tout ceci : du riz à la tonne n'est pas
      // faible à neuf sacs, un carton d'allumettes l'est peut-être.
      await article('RIZ25', stock: 5, seuil: 2);
      await article('ALLUM', stock: 5);

      final lignes = {
        for (final l in await rapports.getReportRows()) l.reference: l
      };
      expect(lignes['RIZ25']!.status, StockStatus.enStock, reason: '5 ≥ 2');
      expect(lignes['ALLUM']!.status, StockStatus.stockFaible,
          reason: '5 < 10');
    });

    test('à zéro veut dire « ne m\'alerte jamais »', () async {
      // Zéro est une décision, pas une absence de réglage : avec un
      // stock à un, l'article reste « en stock ».
      await article('JAMAIS', stock: 1, seuil: 0);

      final ligne = (await rapports.getReportRows()).single;
      expect(ligne.stockMin, 0);
      expect(ligne.status, StockStatus.enStock);
    });

    test('vide n\'est pas zéro', () async {
      await article('SANS', stock: 1);

      expect((await produits.getByReference('SANS'))!.stockMin, isNull);
      expect((await rapports.getReportRows()).single.stockMin, 10);
    });

    test('se retire pour repasser sous celui de l\'entreprise', () async {
      await article('RIZ25', stock: 5, seuil: 2);
      final art = (await produits.getByReference('RIZ25'))!;

      await catalogue.definirSeuilDAlerte(art, null);

      expect((await rapports.getReportRows()).single.stockMin, 10);
    });

    test('refuse un négatif', () async {
      await article('RIZ25', stock: 5);
      final art = (await produits.getByReference('RIZ25'))!;

      await expectLater(
        catalogue.definirSeuilDAlerte(art, -1),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('seuilDAlerte répond même sans réglage', () async {
      await article('SANS', stock: 1);
      final art = (await produits.getByReference('SANS'))!;

      expect(await catalogue.seuilDAlerte(art), 10);
    });
  });

  group('le badge et le compteur', () {
    test('jugent la même ligne sur le même nombre', () async {
      // Le seuil est résolu deux fois — en SQL pour les compteurs, en
      // Dart pour le badge. C'est ce qui attrape leur divergence.
      await article('RIZ25', stock: 5, seuil: 2); // en stock
      await article('ALLUM', stock: 5); // faible, seuil 10
      await article('VIDE', stock: 0); // rupture
      await article('NEG', stock: 0);
      await db.insert('stock_outputs', {
        'date': '2026-01-01',
        'reference': 'NEG',
        'designation': 'NEG',
        'store_id': 1,
        'quantity': 3,
      });

      final counts = await rapports.getStatusCounts();
      final lignes = await rapports.getReportRows();
      int compte(StockStatus s) => lignes.where((l) => l.status == s).length;

      expect(compte(StockStatus.enStock), counts.enStock);
      expect(compte(StockStatus.stockFaible), counts.stockFaible);
      expect(compte(StockStatus.rupture), counts.rupture);
      expect(compte(StockStatus.stockNegatif), counts.negatif);

      expect(counts.enStock, 1, reason: 'RIZ25, sous son propre seuil');
      expect(counts.stockFaible, 1, reason: 'ALLUM, sous celui du défaut');
    });
  });
}
