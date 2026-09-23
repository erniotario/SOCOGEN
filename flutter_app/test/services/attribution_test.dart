import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/auth/session_courante.dart';
import 'package:erp/core/db/schema.dart';
import 'package:erp/modules/stock/models/stock_entry.dart';
import 'package:erp/modules/stock/models/stock_output.dart';
import 'package:erp/modules/stock/repositories/stock_entry_repository.dart';
import 'package:erp/modules/stock/repositories/stock_output_repository.dart';
import 'package:erp/modules/stock/repositories/store_repository.dart';
import 'package:erp/modules/stock/repositories/transaction_repository.dart';
import 'package:erp/modules/stock/repositories/transfert_repository.dart';
import 'package:erp/modules/stock/services/transfert_service.dart';
import 'package:erp/shared/models/transfert.dart';

/// Qui a écrit une ligne du registre.
///
/// L'application avait des comptes et des rôles depuis toujours, mais
/// les mouvements n'enregistraient personne. Deux propriétés à tenir :
/// une écriture en session porte son auteur, et **aucun appelant ne
/// choisit lequel** — sans quoi un formulaire pourrait signer au nom
/// d'un autre.
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
  await db.insert('users', {
    'id': 7,
    'username': 'awa',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'magasinier',
  });
  await db.insert('users', {
    'id': 8,
    'username': 'patron',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'admin',
  });
  return db;
}

void main() {
  late Database db;
  late StockEntryRepository entrees;
  late StockOutputRepository sorties;

  const uneEntree = StockEntry(
    id: 0,
    date: '2026-03-01',
    supplier: 'SONECOMX',
    reference: 'RIZ25',
    designation: 'RIZ',
    storeId: 1,
    quantity: 10,
  );

  setUp(() async {
    db = await _base();
    entrees = StockEntryRepository(database: db);
    sorties = StockOutputRepository(database: db);
    SessionCourante.instance.fermer();
  });

  tearDown(() async {
    SessionCourante.instance.fermer();
    await db.close();
  });

  group('en session', () {
    setUp(() => SessionCourante.instance.ouvrir(utilisateurId: 7, nom: 'awa'));

    test('une entrée porte son auteur', () async {
      await entrees.create(uneEntree);

      final ligne = (await db.query('stock_entries')).single;
      expect(ligne['created_by'], 7);
      expect(ligne['created_at'], isNotNull);
    });

    test('une sortie aussi', () async {
      await sorties.create(const StockOutput(
        id: 0,
        date: '2026-03-01',
        reference: 'RIZ25',
        designation: 'RIZ',
        invoiceNumber: '',
        storeId: 1,
        destination: 'BMC',
        quantity: 5,
      ));

      expect((await db.query('stock_outputs')).single['created_by'], 7);
    });

    test("l'heure d'écriture n'est pas la date du mouvement", () async {
      // Un mouvement peut être antidaté : « saisi le 5 pour le 1er » est
      // précisément ce qu'un registre doit pouvoir dire.
      await entrees.create(uneEntree);

      final ligne = (await db.query('stock_entries')).single;
      expect(ligne['date'], '2026-03-01');
      expect(ligne['created_at'], isNot('2026-03-01'));
      expect(ligne['created_at'] as String, contains('T'));
    });

    test('un transfert signe son en-tête et ses deux mouvements', () async {
      final service = TransfertService(
        transfertRepository: TransfertRepository(database: db),
        storeRepository: StoreRepository(database: db),
      );

      await service.effectuer(
        sourceId: 1,
        destinationId: 2,
        lignes: const [
          LigneTransfert(
            reference: 'RIZ25',
            designation: 'RIZ',
            quantite: 4,
          )
        ],
      );

      expect((await db.query('transferts')).single['created_by'], 7);
      expect((await db.query('stock_outputs')).single['created_by'], 7);
      expect((await db.query('stock_entries')).single['created_by'], 7);
    });
  });

  group("ce qu'un appelant ne peut pas faire", () {
    test('signer au nom de quelqu\'un d\'autre', () async {
      // Le modèle ne porte pas l'auteur, donc il n'y a pas de champ à
      // remplir : le dépôt le lit sur la session au moment d'écrire.
      // C'est ce qui rend l'attribution digne de foi côté application.
      SessionCourante.instance.ouvrir(utilisateurId: 7, nom: 'awa');

      await entrees.create(uneEntree);

      expect((await db.query('stock_entries')).single['created_by'], 7,
          reason: "l'auteur est celui de la session, pas un argument");
    });
  });

  group('hors session', () {
    test("la ligne n'a pas d'auteur plutôt qu'un auteur inventé", () async {
      await entrees.create(uneEntree);

      expect((await db.query('stock_entries')).single['created_by'], isNull);
    });

    test('après déconnexion, plus rien n\'est signé', () async {
      SessionCourante.instance.ouvrir(utilisateurId: 8, nom: 'patron');
      await entrees.create(uneEntree);
      SessionCourante.instance.fermer();
      await entrees.create(uneEntree);

      final lignes = await db.query('stock_entries', orderBy: 'id');
      expect(lignes.first['created_by'], 8);
      expect(lignes.last['created_by'], isNull);
    });
  });

  group("ce que l'historique en montre", () {
    test('le nom, pas l\'identifiant', () async {
      SessionCourante.instance.ouvrir(utilisateurId: 7, nom: 'awa');
      await entrees.create(uneEntree);

      final rows = await TransactionRepository(database: db).getTransactions();
      expect(rows.single.auteur, 'awa');
      expect(rows.single.saisiLe, isNotNull);
    });

    test('une ligne sans auteur se lit comme telle', () async {
      await entrees.create(uneEntree);

      final rows = await TransactionRepository(database: db).getTransactions();
      expect(rows.single.auteur, isNull);
    });
  });
}
