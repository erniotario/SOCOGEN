import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/auth/session_courante.dart';
import 'package:erp/core/db/schema.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/parametres/repositories/tva_repository.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/repositories/stock_repository.dart';
import 'package:erp/modules/stock/services/facture_service.dart';
import 'package:erp/modules/stock/services/paiement_service.dart';
import 'package:erp/modules/stock/services/stock_service.dart';
import 'package:erp/modules/stock/services/vente_service.dart';
import 'package:erp/shared/models/paiement.dart';
import 'package:erp/shared/models/vente.dart';

/// La facture d'une vente.
///
/// Elle n'écrit rien : c'est une seconde lecture, sur A4, de ce que la
/// caisse a déjà inscrit. Ce qu'elle ajoute au ticket est la
/// ventilation de la TVA, et c'est là que les erreurs ne se voient pas
/// — un HT tiré d'un TTC en retirant 19,25 % au lieu de diviser par
/// 1,1925 donne un nombre plausible et faux.
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
        for (final sql in AppSchema.tauxTvaParDefaut) {
          await d.execute(sql);
        }
      },
    ),
  );
  await db.insert('company_settings', {'id': 1, 'name': 'Test', 'devise': 'XAF'});
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
  late FactureService factures;
  late PaiementService reglements;
  late ParametresService parametres;

  LigneVente ligne(String ref, int q, int prix) => LigneVente(
        reference: ref,
        designation: ref,
        quantite: q,
        prixUnitaire: Montant(prix),
      );

  setUp(() async {
    db = await _base();
    parametres = ParametresService(
      settingsRepository: SettingsRepository(database: db),
      tvaRepository: TvaRepository(database: db),
    );
    caisse = VenteService(
      database: db,
      stockService: StockService(stockRepository: StockRepository(database: db)),
      parametresService: parametres,
    );
    reglements = PaiementService(database: db, parametresService: parametres);
    factures = FactureService(
      database: db,
      parametresService: parametres,
      paiementService: reglements,
    );
    SessionCourante.instance.fermer();
  });

  tearDown(() async {
    SessionCourante.instance.fermer();
    await db.close();
  });

  /// Un article, avec le taux nommé par son code (nul : aucun taux).
  Future<void> article(String ref, {String? tva = 'NORMAL', int stock = 100}) async {
    final tvaId = tva == null
        ? null
        : (await db.query('taux_tva', where: 'code = ?', whereArgs: [tva]))
            .single['id'] as int;
    final id = await db.insert('products', {
      'reference': ref,
      'designation': ref,
      'unit': 'unité',
      'tva_id': tvaId,
    });
    await db.insert('product_stocks',
        {'product_id': id, 'store_id': 2, 'initial_stock': stock});
  }

  group('le taux se fige à la vente', () {
    test('celui de la fiche, écrit sur la ligne', () async {
      await article('RIZ25');

      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 11925)]);

      expect((await db.query('stock_outputs')).single['tva_pour_dix_mille'],
          1925);
    });

    test('un changement de taux ne réécrit pas la facture de mars',
        () async {
      // Le même refus que le prix figé : une facture rééditée en
      // décembre doit répéter ce qui a été facturé.
      await article('RIZ25');
      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 11925)]);

      await db.update('taux_tva', {'pour_dix_mille': 500},
          where: 'code = ?', whereArgs: ['NORMAL']);

      final facture = await factures.pour('TKT0000001');
      expect(facture.ventilation.single.taux, const Taux(1925));
    });

    test("un article sans taux prend celui de l'entreprise", () async {
      // C'est ce que le formulaire d'article propose déjà à la
      // création : le figer revient à écrire ce qui était affiché.
      await article('SANSTVA', tva: null);

      await caisse.encaisser(magasinId: 2, lignes: [ligne('SANSTVA', 1, 1000)]);

      expect((await db.query('stock_outputs')).single['tva_pour_dix_mille'],
          1925);
    });

    test('sans taux par défaut, la ligne n\'en porte aucun', () async {
      await db.delete('taux_tva');
      await article('RIZ25', tva: null);

      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 1000)]);

      expect((await db.query('stock_outputs')).single['tva_pour_dix_mille'],
          isNull);
    });
  });

  group('la ventilation', () {
    test('retrouve le HT en divisant, pas en retirant le taux', () async {
      // 11 925 TTC à 19,25 % font 10 000 HT et 1 925 de TVA. Retirer
      // 19,25 % du TTC donnerait 9 629 — plausible et faux.
      await article('RIZ25');
      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 11925)]);

      final facture = await factures.pour('TKT0000001');
      final bloc = facture.ventilation.single;
      expect(bloc.baseHt, const Montant(10000));
      expect(bloc.tva, const Montant(1925));
      expect(bloc.ttc, facture.totalTtc);
    });

    test('un bloc par taux, du plus élevé au plus bas', () async {
      await article('RIZ25');
      await article('LAIT', tva: 'EXONERE');

      await caisse.encaisser(magasinId: 2, lignes: [
        ligne('RIZ25', 1, 11925),
        ligne('LAIT', 2, 500),
      ]);

      final facture = await factures.pour('TKT0000001');
      expect(facture.ventilation.map((v) => v.taux.pourDixMille), [1925, 0]);
      expect(facture.ventilation.last.baseHt, const Montant(1000),
          reason: 'un exonéré a un HT égal à son TTC');
      expect(facture.ventilation.last.tva, const Montant(0));
    });

    test('somme les lignes d\'un taux avant d\'en tirer la TVA', () async {
      // Arrondir chaque ligne puis additionner décale le total de
      // quelques francs, et c'est ce que le client relève.
      await article('A');
      await article('B');
      await caisse.encaisser(magasinId: 2, lignes: [
        ligne('A', 1, 333),
        ligne('B', 1, 333),
      ]);

      final facture = await factures.pour('TKT0000001');
      final bloc = facture.ventilation.single;
      expect(bloc.baseHt + bloc.tva, facture.totalTtc,
          reason: 'HT + TVA doit refaire exactement le TTC');
    });

    test('HT et TVA refont le total', () async {
      await article('RIZ25');
      await article('LAIT', tva: 'EXONERE');
      await caisse.encaisser(magasinId: 2, lignes: [
        ligne('RIZ25', 3, 11925),
        ligne('LAIT', 2, 500),
      ]);

      final facture = await factures.pour('TKT0000001');
      expect(facture.totalHt + facture.totalTva, facture.totalTtc);
    });
  });

  group('ce que la facture refuse de deviner', () {
    test('une ligne sans taux reste hors de la ventilation', () async {
      // « On ne sait pas » n'est pas « exonéré ». La même règle que les
      // lignes sans prix dans la valorisation.
      await article('RIZ25');
      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 11925)]);
      await db.insert('stock_outputs', {
        'date': '2026-03-01',
        'reference': 'VIEUX',
        'designation': 'Ligne d\'avant le figeage',
        'invoice_number': 'TKT0000001',
        'store_id': 2,
        'destination': '',
        'quantity': 1,
        'prix_unitaire': 5000,
      });

      final facture = await factures.pour('TKT0000001');
      expect(facture.estVentilable, isFalse);
      expect(facture.ttcSansTaux, const Montant(5000));
      expect(facture.totalTtc, const Montant(16925),
          reason: 'le TTC non ventilable compte dans le total général');
      expect(facture.ventilation.single.ttc, const Montant(11925),
          reason: 'la ventilation ne porte que ce qui est connu');
    });

    test('une facture entièrement ventilable le dit', () async {
      await article('RIZ25');
      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 11925)]);

      final facture = await factures.pour('TKT0000001');
      expect(facture.estVentilable, isTrue);
      expect(facture.ttcSansTaux, const Montant(0));
    });

    test("un transfert n'est pas une vente et ne se facture pas",
        () async {
      // La marchandise n'a pas quitté l'entreprise : une facture
      // affirmerait une vente qui n'a pas eu lieu.
      await db.insert('transferts', {
        'id': 1,
        'date': '2026-03-01',
        'source_id': 2,
        'destination_id': 2,
      });
      await db.insert('stock_outputs', {
        'date': '2026-03-01',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': 'TRF0000001',
        'store_id': 2,
        'destination': 'Transfert vers Ekie',
        'quantity': 5,
        'transfert_id': 1,
      });

      await expectLater(
        factures.pour('TRF0000001'),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('un numéro sans vente est refusé', () async {
      // Facturer un numéro vide produirait une pièce à zéro qui a l'air
      // valable.
      await expectLater(
        factures.pour('TKT0009999'),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group('ce que la facture rapporte de la vente', () {
    test('son numéro est celui du ticket', () async {
      // Une vente est un événement : lui donner un second numéro parce
      // qu'on la réimprime créerait deux identités pour un seul fait.
      await article('RIZ25');
      final vente =
          await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 1000)]);

      expect((await factures.pour(vente.numeroTicket)).numero,
          vente.numeroTicket);
    });

    test('le magasin, le caissier et les lignes', () async {
      SessionCourante.instance.ouvrir(utilisateurId: 3, nom: 'awa');
      await article('RIZ25');
      await article('LAIT');
      await caisse.encaisser(magasinId: 2, lignes: [
        ligne('RIZ25', 2, 11925),
        ligne('LAIT', 1, 500),
      ]);

      final facture = await factures.pour('TKT0000001');
      expect(facture.magasin, 'BMC');
      expect(facture.caissier, 'awa');
      expect(facture.lignes.map((l) => l.reference), ['RIZ25', 'LAIT']);
    });

    test('le client nommé sur la vente', () async {
      await db.insert('tiers',
          {'id': 9, 'code': 'C1', 'nom': 'MAHIMA', 'type': 'client'});
      await article('RIZ25');
      await caisse.encaisser(
        magasinId: 2,
        lignes: [ligne('RIZ25', 1, 1000)],
        tiersId: 9,
        client: 'MAHIMA',
      );

      expect((await factures.pour('TKT0000001')).client, 'MAHIMA');
    });

    test('ce qui reste dû au moment où on imprime', () async {
      await article('RIZ25');
      await caisse.encaisser(magasinId: 2, lignes: [ligne('RIZ25', 1, 11925)]);

      var facture = await factures.pour('TKT0000001');
      expect(facture.estReglee, isFalse);
      expect(facture.reste, const Montant(11925));

      await reglements.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(11925),
      );

      facture = await factures.pour('TKT0000001');
      expect(facture.estReglee, isTrue);
      expect(facture.regle, const Montant(11925));
    });
  });
}
