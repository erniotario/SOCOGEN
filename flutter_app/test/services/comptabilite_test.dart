import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/auth/session_courante.dart';
import 'package:erp/core/db/schema.dart';
import 'package:erp/core/db/verrou_comptable.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/comptabilite/services/comptabilite_service.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/parametres/repositories/tva_repository.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/modules/stock/models/stock_entry.dart';
import 'package:erp/modules/stock/models/stock_output.dart';
import 'package:erp/modules/stock/repositories/stock_entry_repository.dart';
import 'package:erp/modules/stock/repositories/stock_output_repository.dart';
import 'package:erp/modules/stock/repositories/stock_repository.dart';
import 'package:erp/modules/stock/services/paiement_service.dart';
import 'package:erp/modules/stock/services/stock_service.dart';
import 'package:erp/modules/stock/services/vente_service.dart';
import 'package:erp/shared/models/paiement.dart';
import 'package:erp/shared/models/vente.dart';

/// La clôture comptable, et ce qu'elle rend possible.
///
/// Sans elle, un mouvement de mars pouvait être corrigé en décembre :
/// toute déclaration établie entre-temps devenait invalidable après
/// coup, et une déclaration qu'on peut réécrire ne vaut rien. Ce
/// fichier vérifie donc deux choses inséparables — que le verrou tient
/// sur **tous** les chemins d'écriture, et que la TVA collectée dit ce
/// qu'elle sait sans inventer ce qu'elle ignore.
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
        for (final sql in AppSchema.tauxTvaParDefaut) {
          await d.execute(sql);
        }
      },
    ),
  );
  await db.insert('company_settings', {'id': 1, 'name': 'Test', 'devise': 'XAF'});
  await db.insert('stores', {'id': 1, 'name': 'BMC'});
  await db.insert('users', {
    'id': 4,
    'username': 'awa',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'admin',
  });
  return db;
}

void main() {
  late Database db;
  late ComptabiliteService compta;
  late StockEntryRepository entrees;
  late StockOutputRepository sorties;
  late VenteService caisse;
  late PaiementService reglements;

  setUp(() async {
    db = await _base();
    final parametres = ParametresService(
      settingsRepository: SettingsRepository(database: db),
      tvaRepository: TvaRepository(database: db),
    );
    compta = ComptabiliteService(database: db, parametresService: parametres);
    entrees = StockEntryRepository(database: db);
    sorties = StockOutputRepository(database: db);
    caisse = VenteService(
      database: db,
      stockService: StockService(stockRepository: StockRepository(database: db)),
      parametresService: parametres,
    );
    reglements = PaiementService(database: db, parametresService: parametres);
    VerrouComptable.instance.oublier();
    SessionCourante.instance.fermer();
  });

  tearDown(() async {
    VerrouComptable.instance.oublier();
    SessionCourante.instance.fermer();
    await db.close();
  });

  StockEntry entree({String date = '2026-03-15', int id = 0}) => StockEntry(
        id: id,
        date: date,
        supplier: 'FOURNISSEUR',
        reference: 'RIZ25',
        designation: 'RIZ',
        storeId: 1,
        quantity: 10,
      );

  StockOutput sortie({String date = '2026-03-15', int id = 0}) => StockOutput(
        id: id,
        date: date,
        destination: 'CLIENT',
        invoiceNumber: '',
        reference: 'RIZ25',
        designation: 'RIZ',
        storeId: 1,
        quantity: 2,
      );

  group('fermer une période', () {
    test('pose la limite et la rend opposable', () async {
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      expect(await compta.limiteCourante(), '2026-03-31');
      expect(VerrouComptable.instance.fermeJusquau, '2026-03-31');
      expect(VerrouComptable.instance.estFerme('2026-03-31'), isTrue,
          reason: 'le jour de la limite est inclus');
      expect(VerrouComptable.instance.estFerme('2026-04-01'), isFalse);
    });

    test('rien n\'est fermé tant qu\'on n\'a pas fermé', () async {
      // Une base neuve doit tout accepter : dater d'office une clôture
      // verrouillerait des corrections que personne n'a interdites.
      expect(await compta.charger(), isNull);
      expect(VerrouComptable.instance.estActif, isFalse);
      expect(VerrouComptable.instance.estFerme('2019-01-01'), isFalse);
    });

    test('une date à venir est refusée', () async {
      // Fermer demain empêcherait de saisir la vente de cet
      // après-midi.
      await expectLater(
        compta.cloturer(jusquau: DateTime.now().add(const Duration(days: 2))),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('reculer en silence est refusé', () async {
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      await expectLater(
        compta.cloturer(jusquau: DateTime(2026, 2, 28)),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(await compta.limiteCourante(), '2026-03-31');
    });

    test('fermer davantage avance la limite', () async {
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));
      await compta.cloturer(jusquau: DateTime(2026, 4, 30));

      expect(await compta.limiteCourante(), '2026-04-30');
    });
  });

  group('rouvrir une période', () {
    test('exige un motif', () async {
      // C'est l'acte qu'un contrôle regarde en premier : le laisser se
      // poser sans un mot reviendrait à ne pas le tracer.
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      await expectLater(
        compta.rouvrir(jusquau: DateTime(2026, 2, 28), motif: '   '),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('recule la limite', () async {
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));
      await compta.rouvrir(
        jusquau: DateTime(2026, 2, 28),
        motif: 'Facture fournisseur reçue en retard',
      );

      expect(await compta.limiteCourante(), '2026-02-28');
      expect(VerrouComptable.instance.estFerme('2026-03-15'), isFalse);
    });

    test('peut tout rouvrir', () async {
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));
      await compta.rouvrir(motif: 'Reprise complète du premier trimestre');

      expect(await compta.limiteCourante(), isNull);
      expect(VerrouComptable.instance.estActif, isFalse);
    });

    test('ne sert pas à fermer davantage', () async {
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      await expectLater(
        compta.rouvrir(jusquau: DateTime(2026, 4, 30), motif: 'x'),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('rien à rouvrir quand rien n\'est fermé', () async {
      await expectLater(
        compta.rouvrir(jusquau: DateTime(2026, 1, 1), motif: 'x'),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group("l'historique garde tout", () {
    test('qui a fermé, qui a rouvert, et pourquoi', () async {
      SessionCourante.instance.ouvrir(utilisateurId: 4, nom: 'awa');
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));
      await compta.rouvrir(
        jusquau: DateTime(2026, 2, 28),
        motif: 'Avoir client oublié',
      );

      final actes = await compta.historique();
      expect(actes, hasLength(2));
      expect(actes.first.estUneReouverture, isTrue);
      expect(actes.first.motif, 'Avoir client oublié');
      expect(actes.first.auteur, 'awa');
      expect(actes.first.quand, isNotNull);
      expect(actes.last.estUneReouverture, isFalse,
          reason: 'la première clôture ne recule sur rien');
    });

    test('un acte n\'écrase pas le précédent', () async {
      await compta.cloturer(jusquau: DateTime(2026, 1, 31));
      await compta.cloturer(jusquau: DateTime(2026, 2, 28));
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      expect(await compta.historique(), hasLength(3));
    });
  });

  group('ce que le verrou refuse, sur tous les chemins', () {
    setUp(() async => compta.cloturer(jusquau: DateTime(2026, 3, 31)));

    test('une entrée datée dans le fermé', () async {
      await expectLater(
        entrees.create(entree()),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(await db.query('stock_entries'), isEmpty);
    });

    test('une sortie datée dans le fermé', () async {
      await expectLater(
        sorties.create(sortie()),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('la correction d\'une ligne fermée', () async {
      // Écrite avant la clôture, donc en base.
      await compta.rouvrir(jusquau: DateTime(2026, 1, 1), motif: 'préparation');
      final id = await entrees.create(entree());
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      await expectLater(
        entrees.update(entree(id: id, date: '2026-03-15')),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('sortir une ligne du fermé en la redatant', () async {
      // Sans la vérification de la date **en base**, il suffirait de
      // redater une ligne de mars en avril pour la faire échapper à la
      // période déclarée.
      await compta.rouvrir(jusquau: DateTime(2026, 1, 1), motif: 'préparation');
      final id = await entrees.create(entree());
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      await expectLater(
        entrees.update(entree(id: id, date: '2026-04-02')),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('faire entrer une ligne dans le fermé en la redatant', () async {
      final id = await entrees.create(entree(date: '2026-04-02'));

      await expectLater(
        entrees.update(entree(id: id, date: '2026-03-15')),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('la suppression d\'une ligne fermée', () async {
      await compta.rouvrir(jusquau: DateTime(2026, 1, 1), motif: 'préparation');
      final id = await sorties.create(sortie());
      await compta.cloturer(jusquau: DateTime(2026, 3, 31));

      await expectLater(
        sorties.delete(id),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(await db.query('stock_outputs'), hasLength(1));
    });

    test('une vente encaissée dans le fermé', () async {
      await db.insert('products', {
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'unit': 'sac',
      });

      await expectLater(
        caisse.encaisser(
          magasinId: 1,
          le: DateTime(2026, 3, 15),
          lignes: const [
            LigneVente(
              reference: 'RIZ25',
              designation: 'RIZ',
              quantite: 1,
              prixUnitaire: Montant(11925),
            ),
          ],
        ),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(await db.query('stock_outputs'), isEmpty);
    });

    test('un règlement daté dans le fermé', () async {
      // L'argent aussi fait bouger une période close.
      await expectLater(
        reglements.regler(
          ticket: 'TKT0000001',
          mode: ModePaiement.especes,
          montant: const Montant(5000),
          le: DateTime(2026, 3, 15),
        ),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(await db.query('paiements'), isEmpty);
    });
  });

  group('ce que le verrou laisse passer', () {
    setUp(() async => compta.cloturer(jusquau: DateTime(2026, 3, 31)));

    test('une écriture datée après la limite', () async {
      final id = await entrees.create(entree(date: '2026-04-01'));
      expect(id, greaterThan(0));
    });

    test('la correction d\'une ligne ouverte', () async {
      final id = await entrees.create(entree(date: '2026-04-01'));
      await entrees.update(entree(id: id, date: '2026-04-05'));

      expect((await db.query('stock_entries')).single['date'], '2026-04-05');
    });

    test('un mouvement correctif daté d\'aujourd\'hui', () async {
      // C'est la sortie que le message d'erreur indique : l'original
      // reste debout, la correction porte sa propre date, et la piste
      // se lit.
      final aujourdhui = DateTime.now();
      final id = await sorties.create(sortie(
        date: '${aujourdhui.year}-'
            '${aujourdhui.month.toString().padLeft(2, '0')}-'
            '${aujourdhui.day.toString().padLeft(2, '0')}',
      ));

      expect(id, greaterThan(0));
    });
  });

  group('la TVA collectée', () {
    Future<void> vendre(String date, int ttc, {int? taux = 1925}) =>
        db.insert('stock_outputs', {
          'date': date,
          'reference': 'RIZ25',
          'designation': 'RIZ',
          'invoice_number': 'TKT$date$ttc',
          'store_id': 1,
          'destination': '',
          'quantity': 1,
          'prix_unitaire': ttc,
          'tva_pour_dix_mille': taux,
        });

    test('ventile par taux sur la période demandée', () async {
      await vendre('2026-03-10', 11925);
      await vendre('2026-03-20', 11925);
      await vendre('2026-04-02', 99999); // hors période

      final d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.lignes, hasLength(1));
      expect(d.lignes.single.ttc, const Montant(23850));
      expect(d.lignes.single.baseHt, const Montant(20000));
      expect(d.totalTva, const Montant(3850));
    });

    test('les bornes sont incluses', () async {
      await vendre('2026-03-01', 11925);
      await vendre('2026-03-31', 11925);

      final d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.totalTtc, const Montant(23850));
    });

    test('un taux sans TVA est un taux, pas une absence', () async {
      await vendre('2026-03-10', 11925);
      await vendre('2026-03-11', 5000, taux: 0);

      final d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.lignes.map((l) => l.taux.pourDixMille), [1925, 0]);
      expect(d.lignes.last.tva, const Montant(0));
      expect(d.lignes.last.baseHt, const Montant(5000));
      expect(d.aDesInconnues, isFalse);
    });

    test('un taux inconnu reste hors des bases et dans le total',
        () async {
      await vendre('2026-03-10', 11925);
      await vendre('2026-03-11', 7000, taux: null);

      final d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.ttcSansTaux, const Montant(7000));
      expect(d.lignesSansTaux, 1);
      expect(d.totalTtc, const Montant(18925));
      expect(d.totalHt, const Montant(10000),
          reason: 'la base ne porte que ce qui est connu');
      expect(d.aDesInconnues, isTrue);
    });

    test('une ligne sans prix est signalée, jamais comptée', () async {
      await vendre('2026-03-10', 11925);
      await db.insert('stock_outputs', {
        'date': '2026-03-12',
        'reference': 'VIEUX',
        'designation': 'Sans prix',
        'invoice_number': 'FAC1',
        'store_id': 1,
        'destination': '',
        'quantity': 4,
      });

      final d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.lignesSansPrix, 1);
      expect(d.totalTtc, const Montant(11925));
    });

    test('un transfert ne collecte rien', () async {
      await db.insert('transferts',
          {'id': 1, 'date': '2026-03-10', 'source_id': 1, 'destination_id': 1});
      await db.insert('stock_outputs', {
        'date': '2026-03-10',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'invoice_number': 'TRF1',
        'store_id': 1,
        'destination': '',
        'quantity': 5,
        'prix_unitaire': 11925,
        'tva_pour_dix_mille': 1925,
        'transfert_id': 1,
      });

      final d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.lignes, isEmpty);
      expect(d.totalTtc, const Montant(0));
    });

    test('elle dit si la période peut encore bouger', () async {
      // Une déclaration établie sur une période ouverte peut être
      // démentie le lendemain, et le lecteur doit le savoir.
      await vendre('2026-03-10', 11925);

      var d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.periodeFermee, isFalse);

      await compta.cloturer(jusquau: DateTime(2026, 3, 31));
      d = await compta.tvaCollectee(
        du: DateTime(2026, 3, 1),
        au: DateTime(2026, 3, 31),
      );
      expect(d.periodeFermee, isTrue);
      expect(d.fermeJusquau, '2026-03-31');
    });

    test('une période à l\'envers est refusée', () async {
      await expectLater(
        compta.tvaCollectee(
          du: DateTime(2026, 3, 31),
          au: DateTime(2026, 3, 1),
        ),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });
}
