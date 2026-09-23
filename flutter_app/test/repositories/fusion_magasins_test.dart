import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/modules/stock/repositories/stock_repository.dart';
import 'package:erp/modules/stock/repositories/store_repository.dart';
import 'package:erp/modules/stock/services/stock_service.dart';

/// Réunir deux magasins qui désignent le même dépôt.
///
/// Le cas réel : « Elig-Essono » et « Ellig-Essono ». C'est plus grave
/// qu'un doublon de fiche tiers — le stock étant dérivé **par magasin**,
/// les mouvements d'un même entrepôt se répartissent entre deux soldes
/// qui ne se voient pas, et un article peut paraître en rupture d'un
/// côté et fourni de l'autre.
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
  await db.insert('stores', {'id': 1, 'name': 'Elig-Essono'});
  await db.insert('stores', {'id': 2, 'name': 'Ellig-Essono'});
  await db.insert('stores', {'id': 3, 'name': 'Hysacam'});
  await db.insert('products',
      {'id': 10, 'reference': 'RIZ25', 'designation': 'RIZ', 'unit': 'sac'});
  await db.insert('products',
      {'id': 11, 'reference': 'HUILE', 'designation': 'HUILE', 'unit': 'bidon'});
  return db;
}

void main() {
  late Database db;
  late StoreRepository magasins;
  late StockService stock;

  setUp(() async {
    db = await _base();
    magasins = StoreRepository(database: db);
    stock = StockService(stockRepository: StockRepository(database: db));
  });

  tearDown(() async => db.close());

  Future<void> ouverture(int magasinId, int produitId, int quantite) =>
      db.insert('product_stocks', {
        'product_id': produitId,
        'store_id': magasinId,
        'initial_stock': quantite,
      });

  Future<void> entree(int magasinId, String ref, int quantite) =>
      db.insert('stock_entries', {
        'date': '2026-01-05',
        'supplier': 'SONECOMX',
        'reference': ref,
        'designation': ref,
        'store_id': magasinId,
        'quantity': quantite,
      });

  Future<void> sortie(int magasinId, String ref, int quantite) =>
      db.insert('stock_outputs', {
        'date': '2026-02-05',
        'reference': ref,
        'designation': ref,
        'invoice_number': '',
        'store_id': magasinId,
        'destination': 'BMC',
        'quantity': quantite,
      });

  group('ce que la fusion réunit', () {
    test('les mouvements passent au magasin conservé', () async {
      await ouverture(1, 10, 0);
      await ouverture(2, 10, 0);
      await entree(1, 'RIZ25', 40);
      await sortie(2, 'RIZ25', 10);

      final bilan = await magasins.fusionner(sourceId: 2, cibleId: 1);

      expect(bilan.mouvements, 1);
      expect(await stock.solde(reference: 'RIZ25', magasinId: 1), 30);
    });

    test('le solde du dépôt réuni est la somme des deux moitiés', () async {
      // C'est le tort que la fusion répare : 5 ici et -3 là, ce n'est
      // pas « une rupture », c'est 2 en stock.
      await ouverture(1, 10, 5);
      await ouverture(2, 10, 0);
      await sortie(2, 'RIZ25', 3);
      expect(await stock.solde(reference: 'RIZ25', magasinId: 2), -3);

      await magasins.fusionner(sourceId: 2, cibleId: 1);

      expect(await stock.solde(reference: 'RIZ25', magasinId: 1), 2);
    });

    test("les stocks d'ouverture s'additionnent", () async {
      // `product_stocks` est unique par (article, magasin) : une simple
      // réaffectation violerait la contrainte.
      await ouverture(1, 10, 15);
      await ouverture(2, 10, 25);

      await magasins.fusionner(sourceId: 2, cibleId: 1);

      final lignes = await db.query('product_stocks',
          where: 'product_id = ?', whereArgs: [10]);
      expect(lignes, hasLength(1));
      expect(lignes.single['initial_stock'], 40);
      expect(lignes.single['store_id'], 1);
    });

    test("un article que seule la source portait arrive entier", () async {
      await ouverture(2, 11, 12);

      await magasins.fusionner(sourceId: 2, cibleId: 1);

      final ligne = (await db.query('product_stocks',
              where: 'product_id = ?', whereArgs: [11]))
          .single;
      expect(ligne['store_id'], 1);
      expect(ligne['initial_stock'], 12);
    });
  });

  group('les transferts', () {
    test('suivent le magasin conservé', () async {
      await db.insert('transferts',
          {'date': '2026-03-01', 'source_id': 3, 'destination_id': 2});

      final bilan = await magasins.fusionner(sourceId: 2, cibleId: 1);

      expect(bilan.transferts, 1);
      expect((await db.query('transferts')).single['destination_id'], 1);
    });

    test('un transfert entre les deux reste debout, et s\'annule', () async {
      // Il devient un transfert vers soi-même, ce qui n'a plus de sens
      // comme opération — mais ses deux mouvements se retrouvent dans le
      // même magasin et s'y annulent. Le solde reste juste, et
      // l'historique continue de dire ce qui a été fait ce jour-là.
      await ouverture(1, 10, 20);
      await ouverture(2, 10, 0);
      final t = await db.insert('transferts',
          {'date': '2026-03-01', 'source_id': 1, 'destination_id': 2});
      await db.insert('stock_outputs', {
        'date': '2026-03-01',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': '',
        'store_id': 1,
        'destination': 'Transfert vers Ellig-Essono',
        'quantity': 5,
        'transfert_id': t,
      });
      await db.insert('stock_entries', {
        'date': '2026-03-01',
        'supplier': 'Transfert depuis Elig-Essono',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'store_id': 2,
        'quantity': 5,
        'transfert_id': t,
      });

      await magasins.fusionner(sourceId: 2, cibleId: 1);

      expect(await stock.solde(reference: 'RIZ25', magasinId: 1), 20,
          reason: 'la sortie et l\'entrée se compensent');
      expect(await db.query('transferts'), hasLength(1),
          reason: 'le transfert reste dans l\'historique');
    });
  });

  group('le magasin source', () {
    test('disparaît, parce que plus rien ne le référence', () async {
      // Contrairement à une fiche tiers, qu'on désactive parce qu'elle
      // garde son nom sur les mouvements passés : un magasin vidé n'est
      // plus référencé par rien.
      await ouverture(2, 10, 5);
      await entree(2, 'RIZ25', 10);

      await magasins.fusionner(sourceId: 2, cibleId: 1);

      final restants = await magasins.getAllStores();
      expect(restants.map((m) => m.name), ['Elig-Essono', 'Hysacam']);
    });

    test('laisse un tombstone sous son nom', () async {
      // La synchronisation identifie un magasin par son nom : sans cela,
      // l'appareil voisin le recréerait au prochain échange.
      await magasins.fusionner(sourceId: 2, cibleId: 1);

      final pierres = await db.query('sync_tombstones',
          where: 'table_name = ?', whereArgs: ['stores']);
      expect(pierres.single['merge_key'], 'Ellig-Essono');
    });
  });

  group('ce que la fusion refuse', () {
    test('un magasin avec lui-même', () async {
      await expectLater(
        magasins.fusionner(sourceId: 1, cibleId: 1),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('un magasin inexistant', () async {
      await expectLater(
        magasins.fusionner(sourceId: 99, cibleId: 1),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test("un refus ne laisse aucune trace", () async {
      await ouverture(1, 10, 5);

      await expectLater(
        magasins.fusionner(sourceId: 99, cibleId: 1),
        throwsA(isA<ErreurUtilisateur>()),
      );

      expect(await magasins.getAllStores(), hasLength(3));
      expect(await stock.solde(reference: 'RIZ25', magasinId: 1), 5);
    });
  });
}
