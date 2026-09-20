import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/auth/session_courante.dart';
import 'package:socogen/core/db/schema.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/repositories/settings_repository.dart';
import 'package:socogen/modules/parametres/repositories/tva_repository.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/stock/repositories/stock_repository.dart';
import 'package:socogen/modules/stock/repositories/valorisation_repository.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/stock/services/vente_service.dart';
import 'package:socogen/shared/models/vente.dart';

/// Encaisser au comptoir.
///
/// La vente est la sortie du magasin de la boutique : ce service
/// n'écrit que des sorties. Ce qui en fait une vente tient à trois
/// choses posées sur la ligne — le magasin, le prix pratiqué, et un
/// numéro de ticket partagé.
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
  await db.insert('company_settings', {'id': 1, 'name': 'Test', 'devise': 'XAF'});
  await db.insert('stores', {'id': 1, 'name': 'Hysacam'});
  await db.insert('stores', {'id': 2, 'name': 'BMC'});
  await db.insert('users', {
    'id': 3,
    'username': 'awa',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'magasinier',
  });
  return db;
}

void main() {
  late Database db;
  late VenteService caisse;
  late StockService stock;
  late ValorisationRepository valo;

  LigneVente ligne(String ref, int q, int prix) => LigneVente(
        reference: ref,
        designation: ref,
        quantite: q,
        prixUnitaire: Montant(prix),
      );

  setUp(() async {
    db = await _base();
    stock = StockService(stockRepository: StockRepository(database: db));
    caisse = VenteService(
      database: db,
      stockService: stock,
      parametresService: ParametresService(
        settingsRepository: SettingsRepository(database: db),
        tvaRepository: TvaRepository(database: db),
      ),
    );
    valo = ValorisationRepository(database: db);
    SessionCourante.instance.fermer();
  });

  tearDown(() async {
    SessionCourante.instance.fermer();
    await db.close();
  });

  Future<void> article(String ref, {int stockBmc = 100}) async {
    final id = await db.insert('products', {
      'reference': ref,
      'designation': ref,
      'unit': 'unité',
    });
    await db.insert('product_stocks',
        {'product_id': id, 'store_id': 2, 'initial_stock': stockBmc});
  }

  group('ce que la caisse écrit', () {
    test('une sortie par ligne, dans le magasin de la boutique', () async {
      await article('RIZ25');
      await article('HUILE');

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 2, 18500), ligne('HUILE', 1, 1450)],
      );

      expect(r.lignes, 2);
      final sorties = await db.query('stock_outputs');
      expect(sorties, hasLength(2));
      expect(sorties.every((s) => s['store_id'] == 2), isTrue);
      expect(await stock.solde(reference: 'RIZ25', magasinId: 2), 98);
    });

    test('les lignes partagent le numéro de ticket', () async {
      // C'est ce qui fait d'elles une vente et non deux sorties.
      await article('RIZ25');
      await article('HUILE');

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 1, 18500), ligne('HUILE', 1, 1450)],
      );

      final numeros = (await db.query('stock_outputs'))
          .map((s) => s['invoice_number'])
          .toSet();
      expect(numeros, {r.numeroTicket});
      expect(r.numeroTicket, startsWith('TKT'));
    });

    test('chaque ligne porte le prix pratiqué', () async {
      await article('RIZ25');

      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 3, 18000)]);

      expect((await db.query('stock_outputs')).single['prix_unitaire'], 18000);
    });

    test('et son auteur', () async {
      SessionCourante.instance.ouvrir(utilisateurId: 3, nom: 'awa');
      await article('RIZ25');

      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 18500)]);

      expect((await db.query('stock_outputs')).single['created_by'], 3);
    });

    test('le total est la somme des lignes', () async {
      await article('RIZ25');
      await article('HUILE');

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 2, 18500), ligne('HUILE', 3, 1450)],
      );

      expect(r.total, const Montant(2 * 18500 + 3 * 1450));
    });
  });

  group('les tickets', () {
    test('se suivent sans se marcher dessus', () async {
      await article('RIZ25');

      final premiers = <String>[];
      for (var i = 0; i < 3; i++) {
        premiers.add((await caisse.encaisser(
          magasinId: 2,
          lignes: [ligne('RIZ25', 1, 18500)],
        ))
            .numeroTicket);
      }

      expect(premiers, ['TKT0000001', 'TKT0000002', 'TKT0000003']);
    });

    test('ne se confondent pas avec les factures venues de Sage', () async {
      // Un ticket encaissé ici et une facture importée ne sont pas la
      // même pièce ; les mélanger rendrait la numérotation impossible à
      // reprendre.
      await article('RIZ25');
      await db.insert('stock_outputs', {
        'date': '2026-01-01',
        'reference': 'RIZ25',
        'designation': 'RIZ25',
        'invoice_number': 'FAC0009999',
        'store_id': 2,
        'destination': 'BMC',
        'quantity': 1,
      });

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 1, 18500)],
      );

      expect(r.numeroTicket, 'TKT0000001');
    });

    test('se relisent ligne à ligne', () async {
      await article('RIZ25');
      await article('HUILE');
      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 2, 18500), ligne('HUILE', 1, 1450)],
      );

      final lignes = await caisse.lignesDuTicket(r.numeroTicket);
      expect(lignes.map((l) => l.reference), ['RIZ25', 'HUILE']);
      expect(lignes.first.total, const Montant(37000));
    });
  });

  group('ce que la caisse refuse', () {
    test('un panier vide', () async {
      await expectLater(
        caisse.encaisser(magasinId: 2, lignes: const []),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('une quantité nulle ou négative', () async {
      await article('RIZ25');
      for (final q in [0, -2]) {
        await expectLater(
          caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', q, 18500)]),
          throwsA(isA<ErreurUtilisateur>()),
        );
      }
    });

    test('un prix négatif', () async {
      // Une remise se saisit comme un prix plus bas, pas comme un prix
      // à l'envers.
      await article('RIZ25');
      await expectLater(
        caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, -100)]),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test("un refus n'écrit aucune ligne", () async {
      await article('RIZ25');
      await expectLater(
        caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 0, 18500)]),
        throwsA(isA<ErreurUtilisateur>()),
      );

      expect(await db.query('stock_outputs'), isEmpty);
      expect(await stock.solde(reference: 'RIZ25', magasinId: 2), 100);
    });
  });

  group("ce que la caisse n'impose pas", () {
    test('un article sans prix au catalogue se vend quand même', () async {
      // Refuser rendrait la caisse inutilisable sur les 583 articles
      // sans tarif. C'est le prix *saisi* qui compte, et l'écran en
      // exige un.
      await article('SANSTARIF');

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('SANSTARIF', 1, 2500)],
      );

      expect(r.total, const Montant(2500));
      expect((await db.query('stock_outputs')).single['prix_unitaire'], 2500);
    });

    test('un prix négocié se garde tel quel', () async {
      await article('RIZ25');

      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 17000)]);

      expect((await db.query('stock_outputs')).single['prix_unitaire'], 17000);
    });
  });

  group('le stock négatif', () {
    test('est signalé, pas refusé', () async {
      await article('RIZ25', stockBmc: 2);

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 5, 18500)],
      );

      expect(r.aDesNegatifs, isTrue);
      expect(await stock.solde(reference: 'RIZ25', magasinId: 2), -3,
          reason: 'la marchandise est partie avec le client');
    });

    test("un négatif déjà au dossier n'est pas mis sur cette vente",
        () async {
      await article('RIZ25', stockBmc: 0);
      await db.insert('stock_outputs', {
        'date': '2026-01-01',
        'reference': 'RIZ25',
        'designation': 'RIZ25',
        'store_id': 2,
        'destination': '',
        'quantity': 5,
      });

      final r = await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 1, 18500)],
      );

      expect(r.aDesNegatifs, isFalse);
    });
  });

  group('ce que la vente devient dans les chiffres', () {
    test('elle entre dans le chiffre d\'affaires du magasin', () async {
      await article('RIZ25');

      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 2, 18500)]);

      final bilan = await valo.ventes(magasinId: 2);
      expect(bilan.total, 37000);
      expect(bilan.lignes, 1);
      expect(bilan.lignesSansPrix, 0);
    });
  });
}
