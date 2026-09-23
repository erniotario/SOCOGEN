import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';
import 'package:erp/modules/stock/models/stock_output.dart';
import 'package:erp/modules/stock/repositories/stock_output_repository.dart';
import 'package:erp/modules/stock/repositories/valorisation_repository.dart';

/// Ce que les ventes ont rapporté, et ce que le stock vaut.
///
/// « La vente est la sortie dans le magasin de la boutique » : les
/// sorties valorisées de ce magasin **sont** les ventes. Deux règles à
/// tenir. Le prix est figé sur la ligne, donc un changement de tarif ne
/// réécrit pas le passé. Et un mouvement sans prix est **exclu** des
/// totaux, pas compté pour zéro — « on ne sait pas » et « ça n'a rien
/// rapporté » ne sont pas la même chose.
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
  await db.insert('stores', {'id': 2, 'name': 'BMC'});
  return db;
}

void main() {
  late Database db;
  late ValorisationRepository valo;
  late StockOutputRepository sorties;

  setUp(() async {
    db = await _base();
    valo = ValorisationRepository(database: db);
    sorties = StockOutputRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<int> article(String ref,
      {int? prixAchat, int? prixVente, int stockBmc = 0}) async {
    final id = await db.insert('products', {
      'reference': ref,
      'designation': ref,
      'unit': 'unité',
      'prix_achat': prixAchat,
      'prix_vente': prixVente,
    });
    await db.insert('product_stocks',
        {'product_id': id, 'store_id': 2, 'initial_stock': stockBmc});
    return id;
  }

  Future<void> vendre(String ref, int quantite, int? prix,
      {String date = '2026-03-01', int magasin = 2}) =>
      sorties.create(StockOutput(
        id: 0,
        date: date,
        reference: ref,
        designation: ref,
        invoiceNumber: '',
        storeId: magasin,
        destination: 'Client',
        quantity: quantite,
        prixUnitaireUnites: prix,
      ));

  group('ce que la boutique a vendu', () {
    test('la somme des lignes valorisées', () async {
      await article('RIZ25', prixVente: 18500, stockBmc: 100);
      await vendre('RIZ25', 2, 18500);
      await vendre('RIZ25', 1, 18000); // prix négocié, et c'est réel

      final bilan = await valo.ventes(magasinId: 2);
      expect(bilan.total, 2 * 18500 + 18000);
      expect(bilan.lignes, 2);
    });

    test('un tarif changé ne réécrit pas le passé', () async {
      // La règle qui justifie de figer le prix sur la ligne : une vente
      // de mars doit continuer de rapporter ce qu'elle a rapporté.
      final id = await article('RIZ25', prixVente: 18500, stockBmc: 100);
      await vendre('RIZ25', 2, 18500);

      await db.update('products', {'prix_vente': 25000},
          where: 'id = ?', whereArgs: [id]);

      expect((await valo.ventes(magasinId: 2)).total, 37000);
    });

    test('une ligne sans prix est exclue, et comptée à part', () async {
      // Les 5 201 mouvements d'avant la v10 n'ont pas de prix. Les
      // compter pour zéro ferait passer « on ne sait pas » pour « ça n'a
      // rien rapporté ».
      await article('RIZ25', prixVente: 18500, stockBmc: 100);
      await vendre('RIZ25', 2, 18500);
      await vendre('RIZ25', 5, null);

      final bilan = await valo.ventes(magasinId: 2);
      expect(bilan.total, 37000);
      expect(bilan.lignes, 1);
      expect(bilan.lignesSansPrix, 1);
    });

    test("un transfert n'est pas une vente", () async {
      // La marchandise n'a pas quitté l'entreprise, elle a changé de
      // magasin.
      await article('RIZ25', prixVente: 18500, stockBmc: 100);
      final t = await db.insert('transferts',
          {'date': '2026-03-01', 'source_id': 1, 'destination_id': 2});
      await db.insert('stock_outputs', {
        'date': '2026-03-01',
        'reference': 'RIZ25',
        'designation': 'RIZ25',
        'store_id': 1,
        'destination': 'Transfert vers BMC',
        'quantity': 10,
        'prix_unitaire': 18500,
        'transfert_id': t,
      });

      final bilan = await valo.ventes();
      expect(bilan.total, 0);
      expect(bilan.lignes, 0);
    });

    test('chaque magasin a le sien', () async {
      await article('RIZ25', prixVente: 18500, stockBmc: 100);
      await vendre('RIZ25', 1, 18500, magasin: 2);
      await vendre('RIZ25', 1, 18500, magasin: 1);

      expect((await valo.ventes(magasinId: 2)).total, 18500);
      expect((await valo.ventes()).total, 37000);
    });

    test('la période filtre', () async {
      await article('RIZ25', prixVente: 1000, stockBmc: 100);
      await vendre('RIZ25', 1, 1000, date: '2026-02-15');
      await vendre('RIZ25', 1, 1000, date: '2026-03-10');

      expect(
        (await valo.ventes(du: '2026-03-01', au: '2026-03-31')).total,
        1000,
      );
    });
  });

  group('ce que le stock vaut', () {
    test('au prix d\'achat, pas au prix de vente', () async {
      // La valeur d'un stock est ce qu'il a coûté, pas ce qu'on espère
      // en tirer.
      await article('RIZ25', prixAchat: 15000, prixVente: 18500,
          stockBmc: 4);

      final bilan = await valo.valeurDuStock(magasinId: 2);
      expect(bilan.valeur, 60000);
      expect(bilan.articles, 1);
    });

    test('suit les mouvements', () async {
      await article('RIZ25', prixAchat: 15000, stockBmc: 10);
      await vendre('RIZ25', 4, 18500);

      expect((await valo.valeurDuStock(magasinId: 2)).valeur, 6 * 15000);
    });

    test('un article sans prix est compté à part, pas pour zéro', () async {
      // Son stock est réel, sa valeur est inconnue. Taire la différence
      // ferait passer un inventaire à moitié valorisé pour un
      // inventaire complet.
      await article('RIZ25', prixAchat: 15000, stockBmc: 2);
      await article('SANSPRIX', stockBmc: 50);

      final bilan = await valo.valeurDuStock(magasinId: 2);
      expect(bilan.valeur, 30000);
      expect(bilan.articles, 1);
      expect(bilan.articlesSansPrix, 1);
    });

    test('sans magasin, la valeur de toute la maison', () async {
      await article('RIZ25', prixAchat: 15000, stockBmc: 2);
      await db.insert('product_stocks', {
        'product_id': (await db.query('products')).single['id'],
        'store_id': 1,
        'initial_stock': 3,
      });

      expect((await valo.valeurDuStock()).valeur, 5 * 15000);
    });
  });
}
