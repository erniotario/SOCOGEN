import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/parametres/repositories/tva_repository.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/services/creance_service.dart';
import 'package:erp/shared/models/creance.dart';

/// L'état des créances.
///
/// Rien n'est stocké : l'encours se recalcule des tickets et de leurs
/// règlements. Ce que ce fichier épingle, c'est que la liste dit la
/// vérité dans les cas où l'application ne sait pas tout — un passant
/// qui part sans payer, un ticket sans date lisible — plutôt que de
/// ranger ces sommes quelque part où elles auraient l'air recouvrables.
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
  return db;
}

void main() {
  late Database db;
  late CreanceService creances;

  /// La date d'arrêté de tous les tests : les âges s'en comptent.
  final arrete = DateTime(2026, 9, 24);

  setUp(() async {
    db = await _base();
    creances = CreanceService(
      database: db,
      parametresService: ParametresService(
        settingsRepository: SettingsRepository(database: db),
        tvaRepository: TvaRepository(database: db),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<int> client(String nom, {int? plafond, String? tel}) => db.insert(
        'tiers',
        {
          'code': 'C$nom',
          'nom': nom,
          'type': 'client',
          'plafond_credit': plafond,
          'telephone': tel,
        },
      );

  Future<void> vente(
    String ticket,
    int montant, {
    int? tiersId,
    String date = '2026-09-20',
    int? transfertId,
  }) =>
      db.insert('stock_outputs', {
        'date': date,
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': ticket,
        'store_id': 1,
        'destination': '',
        'quantity': 1,
        'prix_unitaire': montant,
        'tiers_id': tiersId,
        'transfert_id': transfertId,
      });

  Future<void> reglement(String ticket, int montant) => db.insert('paiements', {
        'ticket': ticket,
        'mode': 'especes',
        'montant': montant,
        'date': '2026-09-21',
      });

  group("ce que l'état retient", () {
    test('un ticket soldé disparaît de la liste', () async {
      final id = await client('MAHIMA');
      await vente('TKT0000001', 20000, tiersId: id);
      await reglement('TKT0000001', 20000);

      final etat = await creances.etat(au: arrete);
      expect(etat.clients, isEmpty);
      expect(etat.estVide, isTrue);
    });

    test('un ticket partiellement réglé ne compte que son reste',
        () async {
      final id = await client('MAHIMA');
      await vente('TKT0000001', 20000, tiersId: id);
      await reglement('TKT0000001', 12000);

      final etat = await creances.etat(au: arrete);
      expect(etat.clients.single.encours, const Montant(8000));
      expect(etat.total, const Montant(8000));
    });

    test('un client additionne ses tickets', () async {
      final id = await client('MAHIMA');
      await vente('TKT0000001', 20000, tiersId: id);
      await vente('TKT0000002', 5000, tiersId: id);
      await reglement('TKT0000001', 3000);

      final c = (await creances.etat(au: arrete)).clients.single;
      expect(c.encours, const Montant(22000));
      expect(c.tickets, hasLength(2));
    });

    test('la liste va du plus gros encours au plus petit', () async {
      // C'est l'ordre dans lequel on décroche le téléphone.
      final petit = await client('PETIT');
      final gros = await client('GROS');
      await vente('TKT0000001', 5000, tiersId: petit);
      await vente('TKT0000002', 90000, tiersId: gros);

      expect((await creances.etat(au: arrete)).clients.map((c) => c.nom),
          ['GROS', 'PETIT']);
    });

    test("un transfert ne doit rien à personne", () async {
      await db.insert('transferts',
          {'id': 1, 'date': '2026-09-20', 'source_id': 1, 'destination_id': 1});
      await vente('TRF1', 80000, transfertId: 1);

      expect((await creances.etat(au: arrete)).estVide, isTrue);
    });

    test('une sortie sans numéro n\'est pas une vente à crédit', () async {
      // Les 4 563 sorties d'approvisionnement de l'historique n'ont pas
      // de ticket : les compter comme des créances inventerait une
      // dette de plusieurs millions.
      await db.insert('stock_outputs', {
        'date': '2026-09-20',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': '',
        'store_id': 1,
        'destination': 'BMC',
        'quantity': 10,
        'prix_unitaire': 15900,
      });

      expect((await creances.etat(au: arrete)).estVide, isTrue);
    });
  });

  group("l'âge d'une créance", () {
    test('se compte depuis la date d\'arrêté', () async {
      final id = await client('MAHIMA');
      await vente('TKT0000001', 10000, tiersId: id, date: '2026-09-14');

      final c = (await creances.etat(au: arrete)).clients.single;
      expect(c.joursMax, 10);
      expect(c.tickets.single.tranche, TrancheAge.courant);
    });

    test('se range dans sa tranche', () async {
      final id = await client('MAHIMA');
      await vente('A', 1000, tiersId: id, date: '2026-09-10'); // 14 j
      await vente('B', 2000, tiersId: id, date: '2026-08-10'); // 45 j
      await vente('C', 4000, tiersId: id, date: '2026-07-10'); // 76 j
      await vente('D', 8000, tiersId: id, date: '2026-01-10'); // 257 j

      final etat = await creances.etat(au: arrete);
      expect(etat.parTranche(TrancheAge.courant), const Montant(1000));
      expect(etat.parTranche(TrancheAge.unMois), const Montant(2000));
      expect(etat.parTranche(TrancheAge.deuxMois), const Montant(4000));
      expect(etat.parTranche(TrancheAge.ancien), const Montant(8000));
      expect(etat.total, const Montant(15000));
    });

    test('les bornes tombent où elles doivent', () async {
      expect(TrancheAge.pour(0), TrancheAge.courant);
      expect(TrancheAge.pour(30), TrancheAge.courant);
      expect(TrancheAge.pour(31), TrancheAge.unMois);
      expect(TrancheAge.pour(60), TrancheAge.unMois);
      expect(TrancheAge.pour(61), TrancheAge.deuxMois);
      expect(TrancheAge.pour(90), TrancheAge.deuxMois);
      expect(TrancheAge.pour(91), TrancheAge.ancien);
    });

    test("l'heure de l'impression ne déplace pas une ligne de tranche",
        () async {
      // Sans normalisation à minuit, la même créance changerait de
      // tranche selon qu'on imprime le matin ou le soir.
      final id = await client('MAHIMA');
      await vente('TKT0000001', 10000, tiersId: id, date: '2026-08-25');

      final matin = await creances.etat(au: DateTime(2026, 9, 24, 7, 30));
      final soir = await creances.etat(au: DateTime(2026, 9, 24, 21, 45));
      expect(matin.clients.single.joursMax, soir.clients.single.joursMax);
    });

    test('une date illisible ne rend pas la créance fraîche', () async {
      // Nul n'est pas zéro : le ticket compte dans l'encours et reste
      // hors des tranches, qui le disent.
      final id = await client('MAHIMA');
      await vente('TKT0000001', 7000, tiersId: id, date: 'illisible');

      final etat = await creances.etat(au: arrete);
      expect(etat.total, const Montant(7000));
      expect(etat.ticketsSansDate, 1);
      expect(etat.clients.single.tickets.single.jours, isNull);
      expect(etat.clients.single.joursMax, isNull);
      for (final tranche in TrancheAge.values) {
        expect(etat.parTranche(tranche), const Montant(0), reason: tranche.name);
      }
      expect(etat.aDesReserves, isTrue);
    });
  });

  group('ce qui ne se relance pas', () {
    test('une vente sans fiche client est comptée à part', () async {
      // On ne relance pas un passant : cette somme dit ce que la maison
      // a laissé partir sans savoir à qui.
      final id = await client('MAHIMA');
      await vente('TKT0000001', 20000, tiersId: id);
      await vente('TKT0000002', 6000);

      final etat = await creances.etat(au: arrete);
      expect(etat.total, const Montant(20000));
      expect(etat.sansClient, const Montant(6000));
      expect(etat.ticketsSansClient, 1);
      expect(etat.aDesReserves, isTrue);
    });

    test('elle ne se glisse pas non plus dans les tranches', () async {
      await vente('TKT0000002', 6000, date: '2026-01-01');

      final etat = await creances.etat(au: arrete);
      expect(etat.parTranche(TrancheAge.ancien), const Montant(0));
      expect(etat.sansClient, const Montant(6000));
    });
  });

  group('le plafond de crédit', () {
    test('est dépassé et de combien', () async {
      final id = await client('MAHIMA', plafond: 50000);
      await vente('TKT0000001', 62000, tiersId: id);

      final c = (await creances.etat(au: arrete)).clients.single;
      expect(c.depassePlafond, isTrue);
      expect(c.depassement, const Montant(12000));
    });

    test('tenir exactement dedans ne le dépasse pas', () async {
      final id = await client('MAHIMA', plafond: 50000);
      await vente('TKT0000001', 50000, tiersId: id);

      expect((await creances.etat(au: arrete)).clients.single.depassePlafond,
          isFalse);
    });

    test("pas de plafond n'est pas un plafond à zéro", () async {
      final sans = await client('SANS');
      final zero = await client('ZERO', plafond: 0);
      await vente('A', 90000, tiersId: sans);
      await vente('B', 1, tiersId: zero);

      final etat = await creances.etat(au: arrete);
      final parNom = {for (final c in etat.clients) c.nom: c};
      expect(parNom['SANS']!.depassePlafond, isFalse);
      expect(parNom['ZERO']!.depassePlafond, isTrue,
          reason: 'zéro interdit tout crédit, et c\'est une décision');
      expect(etat.auDessusDuPlafond.map((c) => c.nom), ['ZERO']);
    });
  });

  group("l'état porte sa date", () {
    test('celle qu\'on lui a donnée, pas celle du jour', () async {
      // C'est ce qui permet de rééditer l'état du 31 du mois dernier et
      // de retrouver les mêmes tranches.
      expect((await creances.etat(au: DateTime(2026, 8, 31))).arreteAu,
          '2026-08-31');
    });
  });

  group('ce que la fiche apporte à la relance', () {
    test('le code et le téléphone du client', () async {
      final id = await client('MAHIMA', tel: '699000000');
      await vente('TKT0000001', 20000, tiersId: id);

      final c = (await creances.etat(au: arrete)).clients.single;
      expect(c.code, 'CMAHIMA');
      expect(c.telephone, '699000000');
      expect(c.tickets.single.ticket, 'TKT0000001');
    });

    test('les tickets vont du plus ancien au plus récent', () async {
      // On relance en commençant par ce qui traîne le plus.
      final id = await client('MAHIMA');
      await vente('RECENT', 1000, tiersId: id, date: '2026-09-20');
      await vente('ANCIEN', 1000, tiersId: id, date: '2026-05-02');

      expect(
        (await creances.etat(au: arrete)).clients.single.tickets
            .map((t) => t.ticket),
        ['ANCIEN', 'RECENT'],
      );
    });
  });
}
