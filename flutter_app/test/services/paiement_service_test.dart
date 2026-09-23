import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/auth/session_courante.dart';
import 'package:socogen/core/db/schema.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/repositories/settings_repository.dart';
import 'package:socogen/modules/parametres/repositories/tva_repository.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/modules/stock/services/paiement_service.dart';
import 'package:socogen/shared/models/paiement.dart';

/// Ce qui a été payé, et ce qui reste dû.
///
/// Le crédit n'est pas un mode de paiement : c'est l'absence de
/// paiement. Le reste dû se calcule — total des lignes moins somme des
/// règlements — plutôt que de se stocker, parce qu'un solde stocké
/// diverge du jour où une ligne est corrigée.
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
  await db.insert('stores', {'id': 1, 'name': 'BMC'});
  await db.insert('users', {
    'id': 5,
    'username': 'awa',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'magasinier',
  });
  await db.insert('tiers', {
    'id': 9,
    'code': 'C0001',
    'nom': 'MAHIMA',
    'type': 'client',
    'plafond_credit': 50000,
  });
  return db;
}

void main() {
  late Database db;
  late PaiementService caisse;

  setUp(() async {
    db = await _base();
    caisse = PaiementService(
      database: db,
      parametresService: ParametresService(
        settingsRepository: SettingsRepository(database: db),
        tvaRepository: TvaRepository(database: db),
      ),
    );
    SessionCourante.instance.fermer();
  });

  tearDown(() async {
    SessionCourante.instance.fermer();
    await db.close();
  });

  /// Une vente d'un montant donné, sur un ticket donné.
  Future<void> vente(String ticket, int montant, {int? tiersId}) =>
      db.insert('stock_outputs', {
        'date': '2026-03-01',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': ticket,
        'store_id': 1,
        'destination': 'Client',
        'quantity': 1,
        'prix_unitaire': montant,
        'tiers_id': tiersId,
      });

  group('le solde d\'un ticket', () {
    test('part du total des lignes', () async {
      await vente('TKT0000001', 18500);

      final solde = await caisse.solde('TKT0000001');
      expect(solde.total, const Montant(18500));
      expect(solde.regle, const Montant(0));
      expect(solde.reste, const Montant(18500));
      expect(solde.estRegle, isFalse);
    });

    test('diminue à chaque règlement', () async {
      await vente('TKT0000001', 18500);

      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(10000),
      );

      var solde = await caisse.solde('TKT0000001');
      expect(solde.reste, const Montant(8500));
      expect(solde.estRegle, isFalse);

      // Espèces puis Mobile Money sur le même ticket : le quotidien.
      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.mobileMoney,
        montant: const Montant(8500),
        reference: 'MP260301.1234.A56789',
      );

      solde = await caisse.solde('TKT0000001');
      expect(solde.reste, const Montant(0));
      expect(solde.estRegle, isTrue);
    });

    test('un trop-perçu est de la monnaie, pas une dette', () async {
      // Le client tend 20 000 pour 18 500 : la caisse rend 1 500, et
      // l'entreprise ne lui doit rien.
      await vente('TKT0000001', 18500);
      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(20000),
      );

      final solde = await caisse.solde('TKT0000001');
      expect(solde.rendu, const Montant(1500));
      expect(solde.reste, const Montant(0));
      expect(solde.estRegle, isTrue);
    });

    test('suit une ligne corrigée après coup', () async {
      // C'est pourquoi le solde se calcule et ne se stocke pas.
      await vente('TKT0000001', 18500);
      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(18500),
      );
      expect((await caisse.solde('TKT0000001')).estRegle, isTrue);

      await db.update('stock_outputs', {'quantity': 2},
          where: 'invoice_number = ?', whereArgs: ['TKT0000001']);

      final solde = await caisse.solde('TKT0000001');
      expect(solde.total, const Montant(37000));
      expect(solde.reste, const Montant(18500));
    });
  });

  group('ce qu\'un règlement refuse', () {
    test('un montant nul ou négatif', () async {
      // Un remboursement est un avoir, pas un paiement à l'envers.
      for (final m in [const Montant(0), const Montant(-500)]) {
        await expectLater(
          caisse.regler(
            ticket: 'TKT0000001',
            mode: ModePaiement.especes,
            montant: m,
          ),
          throwsA(isA<ErreurUtilisateur>()),
        );
      }
    });

    test('un Mobile Money sans numéro de transaction', () async {
      // C'est la trace qui permet de retrouver l'argent chez l'opérateur
      // quand un client conteste.
      await expectLater(
        caisse.regler(
          ticket: 'TKT0000001',
          mode: ModePaiement.mobileMoney,
          montant: const Montant(5000),
        ),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('mais les espèces n\'en demandent pas', () async {
      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(5000),
      );

      expect(await caisse.reglementsDe('TKT0000001'), hasLength(1));
    });
  });

  group('le règlement porte son auteur', () {
    test('celui de la session', () async {
      SessionCourante.instance.ouvrir(utilisateurId: 5, nom: 'awa');

      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(5000),
      );

      expect((await db.query('paiements')).single['created_by'], 5);
    });
  });

  group("l'encours d'un client", () {
    test('somme ses tickets impayés', () async {
      await vente('TKT0000001', 18500, tiersId: 9);
      await vente('TKT0000002', 12000, tiersId: 9);
      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(10000),
      );

      expect(await caisse.encoursDe(9), const Montant(20500));
    });

    test('ignore les ventes qui ne lui sont pas rattachées', () async {
      await vente('TKT0000001', 18500, tiersId: 9);
      await vente('TKT0000002', 99000); // un passant

      expect(await caisse.encoursDe(9), const Montant(18500));
    });

    test('ne descend pas sous zéro', () async {
      await vente('TKT0000001', 10000, tiersId: 9);
      await caisse.regler(
        ticket: 'TKT0000001',
        mode: ModePaiement.especes,
        montant: const Montant(15000),
      );

      expect(await caisse.encoursDe(9), const Montant(0));
    });
  });

  group('le plafond de crédit', () {
    test('laisse passer ce qui tient dedans', () async {
      await vente('TKT0000001', 20000, tiersId: 9);

      final message = await caisse.depassementDePlafond(
        tiersId: 9,
        plafond: const Montant(50000),
        aCrediter: const Montant(25000),
      );

      expect(message, isNull);
    });

    test('nomme les trois nombres quand il est dépassé', () async {
      // Un refus qui ne dit pas de combien on dépasse n'aide personne à
      // décider.
      await vente('TKT0000001', 40000, tiersId: 9);

      final message = await caisse.depassementDePlafond(
        tiersId: 9,
        plafond: const Montant(50000),
        aCrediter: const Montant(20000),
      );

      expect(message, isNotNull);
      expect(message, contains('40'));
      expect(message, contains('20'));
      expect(message, contains('50'));
    });

    test('pas de plafond n\'est pas un plafond à zéro', () async {
      await vente('TKT0000001', 900000, tiersId: 9);

      expect(
        await caisse.depassementDePlafond(
          tiersId: 9,
          plafond: null,
          aCrediter: const Montant(500000),
        ),
        isNull,
      );
      expect(
        await caisse.depassementDePlafond(
          tiersId: 9,
          plafond: const Montant(0),
          aCrediter: const Montant(1),
        ),
        isNotNull,
        reason: 'un plafond à zéro interdit tout crédit, et c\'est une '
            'décision',
      );
    });

    test('une vente réglée comptant ne consomme rien', () async {
      final message = await caisse.depassementDePlafond(
        tiersId: 9,
        plafond: const Montant(50000),
        aCrediter: const Montant(0),
      );

      expect(message, isNull);
    });
  });
}
