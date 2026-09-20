import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/db/schema.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/modules/stock/repositories/stock_repository.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/modules/stock/repositories/transfert_repository.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/services/transfert_service.dart';
import 'package:socogen/shared/models/transfert.dart';

/// Le transfert entre magasins.
///
/// Ce que l'opération doit garantir : la marchandise ne quitte pas
/// l'entreprise, les deux magasins bougent ensemble, et l'historique
/// reste lisible sans suivre le lien.
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
  await db.insert('stores', {'id': 2, 'name': 'Ekie'});
  final riz = await db.insert('products', {
    'reference': 'RIZ25',
    'designation': 'RIZ PERLE 25KG',
    'unit': 'sac',
  });
  await db.insert('product_stocks',
      {'product_id': riz, 'store_id': 1, 'initial_stock': 40});
  await db.insert('product_stocks',
      {'product_id': riz, 'store_id': 2, 'initial_stock': 0});
  return db;
}

void main() {
  late Database db;
  late TransfertService service;
  late StockService stock;

  const riz = LigneTransfert(
    reference: 'RIZ25',
    designation: 'RIZ PERLE 25KG',
    quantite: 10,
  );

  setUp(() async {
    db = await _base();
    stock = StockService(stockRepository: StockRepository(database: db));
    service = TransfertService(
      transfertRepository: TransfertRepository(database: db),
      storeRepository: StoreRepository(database: db),
      stockService: stock,
    );
  });

  tearDown(() async => db.close());

  Future<int> solde(int magasinId) =>
      stock.solde(reference: 'RIZ25', magasinId: magasinId);

  group('ce que le transfert déplace', () {
    test('retire ici et ajoute là, du même nombre', () async {
      await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [riz],
      );

      expect(await solde(1), 30);
      expect(await solde(2), 10);
    });

    test("le total de l'entreprise ne bouge pas", () async {
      // C'est tout l'objet : la marchandise n'a pas quitté la maison.
      final avant = await solde(1) + await solde(2);

      await service.effectuer(sourceId: 1, destinationId: 2, lignes: [riz]);

      expect(await solde(1) + await solde(2), avant);
    });

    test('plusieurs articles en une opération', () async {
      await db.insert('products',
          {'reference': 'HUILE', 'designation': 'HUILE 5L', 'unit': 'bidon'});
      await db.insert('stock_entries', {
        'date': '2026-01-01',
        'reference': 'HUILE',
        'designation': 'HUILE 5L',
        'store_id': 1,
        'quantity': 12,
      });

      final resultat = await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [
          riz,
          const LigneTransfert(
            reference: 'HUILE',
            designation: 'HUILE 5L',
            quantite: 5,
          ),
        ],
      );

      expect(resultat.lignesDeplacees, 2);
      expect(await stock.solde(reference: 'HUILE', magasinId: 2), 5);
      expect(await service.lignesDe(resultat.transfertId), hasLength(2));
    });
  });

  group("ce qu'on lit dans l'historique", () {
    test('les deux mouvements portent le même transfert', () async {
      final resultat = await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [riz],
      );

      final sortie = (await db.query('stock_outputs')).single;
      final entree = (await db.query('stock_entries')).single;
      expect(sortie['transfert_id'], resultat.transfertId);
      expect(entree['transfert_id'], resultat.transfertId);
    });

    test('chaque ligne dit où la marchandise va et d\'où elle vient',
        () async {
      // Lisible sans suivre le lien : quelqu'un qui relit Transactions
      // dans six mois voit le déplacement, même sans ouvrir l'écran des
      // transferts.
      await service.effectuer(sourceId: 1, destinationId: 2, lignes: [riz]);

      expect((await db.query('stock_outputs')).single['destination'],
          'Transfert vers Ekie');
      expect((await db.query('stock_entries')).single['supplier'],
          'Transfert depuis Hysacam');
    });

    test('le transfert ne recopie ni référence ni quantité', () async {
      // L'en-tête ne porte que l'opération ; les mouvements sont la
      // seule source de ce qui a bougé, donc rien ne peut diverger.
      final resultat = await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [riz],
      );

      final entete = (await db.query('transferts')).single;
      expect(entete.keys, isNot(contains('reference')));
      expect(entete.keys, isNot(contains('quantity')));
      expect(entete['source_id'], 1);
      expect(entete['destination_id'], 2);
      expect((await service.lignesDe(resultat.transfertId)).single.quantite, 10);
    });
  });

  group('ce que le service refuse', () {
    test('un transfert vers le même magasin', () async {
      await expectLater(
        service.effectuer(sourceId: 1, destinationId: 1, lignes: [riz]),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('une quantité nulle ou négative', () async {
      // Une quantité négative inverserait le sens du transfert sans le
      // dire, ce qui est la pire façon de le faire.
      for (final q in [0, -5]) {
        await expectLater(
          service.effectuer(
            sourceId: 1,
            destinationId: 2,
            lignes: [
              LigneTransfert(
                reference: 'RIZ25',
                designation: 'RIZ',
                quantite: q,
              )
            ],
          ),
          throwsA(isA<ErreurUtilisateur>()),
        );
      }
    });

    test('une liste vide', () async {
      await expectLater(
        service.effectuer(sourceId: 1, destinationId: 2, lignes: const []),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('un refus n\'écrit rien du tout', () async {
      await expectLater(
        service.effectuer(sourceId: 1, destinationId: 1, lignes: [riz]),
        throwsA(isA<ErreurUtilisateur>()),
      );

      expect(await db.query('transferts'), isEmpty);
      expect(await db.query('stock_outputs'), isEmpty);
      expect(await db.query('stock_entries'), isEmpty);
      expect(await solde(1), 40);
    });
  });

  group('le stock négatif', () {
    test('est signalé, pas refusé', () async {
      // De la marchandise physiquement partie doit pouvoir être
      // enregistrée ; l'écart ne doit simplement pas passer inaperçu.
      final resultat = await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [
          const LigneTransfert(
            reference: 'RIZ25',
            designation: 'RIZ',
            quantite: 50,
          )
        ],
      );

      expect(resultat.aDesNegatifs, isTrue);
      expect(resultat.negatifs.single, contains('Hysacam'));
      expect(await solde(1), -10, reason: 'le transfert a bien eu lieu');
      expect(await solde(2), 50);
    });

    test("un négatif déjà au dossier n'est pas mis sur ce transfert",
        () async {
      // Un avertissement qui se déclenche à chaque fois est un
      // avertissement qu'on apprend à ignorer.
      await db.insert('stock_outputs', {
        'date': '2026-01-01',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'store_id': 1,
        'quantity': 60,
      });
      expect(await solde(1), -20);

      final resultat = await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [
          const LigneTransfert(
            reference: 'RIZ25',
            designation: 'RIZ',
            quantite: 5,
          )
        ],
      );

      expect(resultat.aDesNegatifs, isFalse);
    });

    test('un transfert qui reste positif ne dit rien', () async {
      final resultat = await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: [riz],
      );

      expect(resultat.aDesNegatifs, isFalse);
    });
  });

  group('la liste', () {
    test('rend les noms des magasins et le compte de lignes', () async {
      await service.effectuer(sourceId: 1, destinationId: 2, lignes: [riz]);

      final liste = await service.lister();
      expect(liste, hasLength(1));
      expect(liste.single.source, 'Hysacam');
      expect(liste.single.destination, 'Ekie');
      expect(liste.single.lignes, 1,
          reason: 'compté sur les sorties : les compter sur les deux '
              'tables doublerait le résultat');
    });
  });
}
