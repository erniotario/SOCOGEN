import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/parametres/repositories/tva_repository.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/services/cloture_service.dart';
import 'package:erp/shared/models/paiement.dart';

/// La clôture de caisse.
///
/// Tout ce fichier tourne autour d'une seule distinction : **vendu** et
/// **encaissé** ne sont pas le même chiffre. Un ticket parti à crédit
/// gonfle le premier sans rien mettre dans le tiroir ; une créance de
/// la semaine dernière réglée ce matin fait l'inverse. Les confondre
/// est la raison ordinaire pour laquelle une caisse ne tombe pas juste.
Future<Database> _base() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      singleInstance: false,
      onCreate: (d, _) async {
        for (final sql in AppSchema.createStatements) {
          await d.execute(sql);
        }
      },
    ),
  );
  await db.insert('company_settings', {'id': 1, 'name': 'Test', 'devise': 'XAF'});
  await db.insert('stores', {'id': 1, 'name': 'BMC'});
  await db.insert('stores', {'id': 2, 'name': 'Hysacam'});
  return db;
}

void main() {
  late Database db;
  late ClotureService cloture;

  const jour = '2026-09-24';
  const veille = '2026-09-23';

  setUp(() async {
    db = await _base();
    cloture = ClotureService(
      database: db,
      parametresService: ParametresService(
        settingsRepository: SettingsRepository(database: db),
        tvaRepository: TvaRepository(database: db),
      ),
    );
  });

  tearDown(() async => db.close());

  /// Une ligne de vente : un ticket, un prix TTC, un taux.
  Future<void> vente(
    String ticket,
    int prix, {
    String date = jour,
    int magasin = 1,
    int quantite = 1,
    int? taux = 1925,
    int? transfertId,
  }) =>
      db.insert('stock_outputs', {
        'date': date,
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': ticket,
        'store_id': magasin,
        'destination': '',
        'quantity': quantite,
        'prix_unitaire': prix,
        'tva_pour_dix_mille': taux,
        'transfert_id': transfertId,
      });

  Future<void> reglement(
    String ticket,
    int montant, {
    String date = jour,
    ModePaiement mode = ModePaiement.especes,
  }) =>
      db.insert('paiements', {
        'ticket': ticket,
        'mode': mode.code,
        'montant': montant,
        'date': date,
      });

  group('ce qui a été vendu', () {
    test('le total TTC et le nombre de tickets', () async {
      await vente('TKT0000001', 11925);
      await vente('TKT0000001', 5000);
      await vente('TKT0000002', 2000);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.tickets, 2, reason: 'deux tickets, trois lignes');
      expect(c.ventesTtc, const Montant(18925));
    });

    test("la veille n'y entre pas", () async {
      await vente('TKT0000001', 11925);
      await vente('TKT0000000', 99000, date: veille);

      expect((await cloture.pour(date: jour, magasinId: 1)).ventesTtc,
          const Montant(11925));
    });

    test('un autre magasin non plus', () async {
      await vente('TKT0000001', 11925);
      await vente('TKT0000002', 7000, magasin: 2);

      expect((await cloture.pour(date: jour, magasinId: 1)).ventesTtc,
          const Montant(11925));
      expect((await cloture.pour(date: jour)).ventesTtc,
          const Montant(18925),
          reason: 'sans magasin, la clôture porte sur tous');
    });

    test("un transfert n'est pas une vente", () async {
      // La marchandise n'a pas quitté l'entreprise.
      await db.insert('transferts', {
        'id': 1,
        'date': jour,
        'source_id': 1,
        'destination_id': 2,
      });
      await vente('TKT0000001', 11925);
      await vente('TRF1', 50000, transfertId: 1);

      expect((await cloture.pour(date: jour, magasinId: 1)).ventesTtc,
          const Montant(11925));
    });

    test('une ligne sans prix est comptée à part, pas à zéro', () async {
      // « On ne sait pas » n'est pas « ça n'a rien rapporté ».
      await vente('TKT0000001', 11925);
      await db.insert('stock_outputs', {
        'date': jour,
        'reference': 'VIEUX',
        'designation': 'Sans prix',
        'invoice_number': 'TKT0000002',
        'store_id': 1,
        'destination': '',
        'quantity': 3,
      });

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.ventesTtc, const Montant(11925));
      expect(c.lignesSansPrix, 1);
      expect(c.aDesInconnues, isTrue);
      expect(c.tickets, 2,
          reason: 'la ligne existe même si son prix est inconnu');
    });
  });

  group('la TVA collectée', () {
    test('se ventile par taux comme sur la facture', () async {
      await vente('TKT0000001', 11925);
      await vente('TKT0000002', 1000, taux: 0);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.tva.map((v) => v.taux.pourDixMille), [1925, 0]);
      expect(c.tva.first.tva, const Montant(1925));
      expect(c.totalTva, const Montant(1925));
    });

    test('le TTC sans taux reste hors ventilation mais dans le total',
        () async {
      await vente('TKT0000001', 11925);
      await vente('TKT0000002', 4000, taux: null);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.ventesTtc, const Montant(15925));
      expect(c.ttcSansTaux, const Montant(4000));
      expect(c.totalTva, const Montant(1925),
          reason: 'la TVA ne se devine pas sur une ligne sans taux');
      expect(c.aDesInconnues, isTrue);
    });
  });

  group('ce qui est entré dans le tiroir', () {
    test('par mode, avec le compte des opérations', () async {
      await vente('TKT0000001', 20000);
      await reglement('TKT0000001', 12000);
      await reglement('TKT0000001', 8000, mode: ModePaiement.mobileMoney);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.encaisseTotal, const Montant(20000));
      expect(c.especes, const Montant(12000));
      expect(c.encaisse.map((e) => e.mode),
          [ModePaiement.especes, ModePaiement.mobileMoney]);
      expect(c.encaisse.first.operations, 1);
    });

    test('les espèces se comptent seules', () async {
      // Le Mobile Money se vérifie chez l'opérateur ; le mêler au fond
      // de caisse rend un écart introuvable.
      await vente('TKT0000001', 20000);
      await reglement('TKT0000001', 20000, mode: ModePaiement.mobileMoney);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.encaisseTotal, const Montant(20000));
      expect(c.especes, const Montant(0));
    });
  });

  group('vendu et encaissé ne sont pas le même chiffre', () {
    test('un ticket à crédit gonfle le vendu et pas le tiroir', () async {
      await vente('TKT0000001', 20000);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.ventesTtc, const Montant(20000));
      expect(c.encaisseTotal, const Montant(0));
      expect(c.creditAccorde, const Montant(20000));
    });

    test('une créance réglée aujourd\'hui remplit le tiroir sans rien '
        'vendre', () async {
      await vente('TKT0000000', 30000, date: veille);
      await reglement('TKT0000000', 30000);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.ventesTtc, const Montant(0));
      expect(c.tickets, 0);
      expect(c.encaisseTotal, const Montant(30000));
      expect(c.encaisseSurCreances, const Montant(30000));
      expect(c.encaisseDuJour, const Montant(0));
    });

    test('les deux se distinguent dans la même journée', () async {
      await vente('TKT0000000', 30000, date: veille);
      await reglement('TKT0000000', 30000);
      await vente('TKT0000001', 20000);
      await reglement('TKT0000001', 5000);

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.ventesTtc, const Montant(20000));
      expect(c.encaisseTotal, const Montant(35000));
      expect(c.encaisseDuJour, const Montant(5000));
      expect(c.encaisseSurCreances, const Montant(30000));
      expect(c.creditAccorde, const Montant(15000));
    });

    test('un ticket du jour réglé le lendemain n\'était pas du crédit '
        'ce soir-là', () async {
      // Le crédit accordé se mesure sur ce qui reste dû, et il reste dû
      // au moment où on lit la clôture — pas au moment de la vente.
      await vente('TKT0000001', 20000);
      await reglement('TKT0000001', 20000, date: '2026-09-25');

      final c = await cloture.pour(date: jour, magasinId: 1);
      expect(c.creditAccorde, const Montant(0));
      expect(c.encaisseTotal, const Montant(0),
          reason: 'ce règlement appartient au tiroir du lendemain');
    });

    test('un trop-perçu ne rend pas le crédit négatif', () async {
      await vente('TKT0000001', 20000);
      await reglement('TKT0000001', 25000);

      expect((await cloture.pour(date: jour, magasinId: 1)).creditAccorde,
          const Montant(0));
    });
  });

  group('une journée sans rien', () {
    test('se lit comme vide plutôt que de lever', () async {
      final c = await cloture.pour(date: jour, magasinId: 1);

      expect(c.estVide, isTrue);
      expect(c.ventesTtc, const Montant(0));
      expect(c.encaisse, isEmpty);
      expect(c.aDesInconnues, isFalse);
    });
  });
}
