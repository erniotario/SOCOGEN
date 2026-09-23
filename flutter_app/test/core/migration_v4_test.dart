import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/schema.dart';
import 'package:erp/modules/catalogue/models/product.dart';

/// La montée en v4 sur une base qui contient déjà du travail.
///
/// L'installation du client porte 723 articles, 631 entrées et 4 570
/// sorties. Une migration qui les abîme ne se rattrape pas : ce test
/// rejoue la v3 telle qu'elle existe chez lui, applique la migration, et
/// vérifie que tout est encore là.
///
/// Il vérifie le SQL, pas le branchement dans `DatabaseService` — ce
/// dernier tient en quatre lignes visibles à l'œil, alors que les
/// instructions ci-dessous sont ce qui peut réellement mal tourner.
/// Reste une limite qu'aucun test d'ici ne lève : Android refuse toute
/// instruction qui retourne des lignes, et seule une exécution sur
/// appareil le dira.

/// Le schéma v3, figé tel qu'il était avant cette phase.
const List<String> _schemaV3 = [
  '''
  CREATE TABLE stores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    updated_at TEXT
  )
  ''',
  '''
  CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reference TEXT NOT NULL UNIQUE,
    designation TEXT NOT NULL,
    unit TEXT DEFAULT 'unité',
    updated_at TEXT
  )
  ''',
  '''
  CREATE TABLE product_stocks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    initial_stock INTEGER DEFAULT 0,
    updated_at TEXT,
    UNIQUE(product_id, store_id)
  )
  ''',
  '''
  CREATE TABLE stock_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    supplier TEXT DEFAULT '',
    reference TEXT NOT NULL,
    designation TEXT NOT NULL,
    store_id INTEGER NOT NULL REFERENCES stores(id),
    quantity INTEGER NOT NULL,
    sync_id TEXT,
    updated_at TEXT
  )
  ''',
  '''
  CREATE TABLE stock_outputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    reference TEXT NOT NULL,
    designation TEXT NOT NULL,
    invoice_number TEXT DEFAULT '',
    store_id INTEGER NOT NULL REFERENCES stores(id),
    destination TEXT DEFAULT '',
    quantity INTEGER NOT NULL,
    sync_id TEXT,
    updated_at TEXT
  )
  ''',
  '''
  CREATE TABLE sync_tombstones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    merge_key TEXT NOT NULL,
    deleted_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT
  )
  ''',
  '''
  CREATE TABLE company_settings (
    id INTEGER PRIMARY KEY,
    name TEXT DEFAULT '',
    address TEXT DEFAULT '',
    city TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    email TEXT DEFAULT '',
    website TEXT DEFAULT '',
    tax_id TEXT DEFAULT '',
    rccm TEXT DEFAULT '',
    logo_path TEXT DEFAULT ''
  )
  ''',
];

Future<Database> _ouvrirV3AvecDonnees() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 3, singleInstance: false),
  );
  for (final sql in _schemaV3) {
    await db.execute(sql);
  }
  await db.insert('stores', {'id': 1, 'name': 'Hysacam'});
  await db.insert('products', {
    'id': 1,
    'reference': 'RIZMM25',
    'designation': 'RIZ MM 25KG',
    'unit': 'sac',
  });
  await db.insert('product_stocks', {
    'product_id': 1,
    'store_id': 1,
    'initial_stock': 40,
  });
  await db.insert('stock_entries', {
    'date': '2026-01-05',
    'supplier': 'SOCACIM',
    'reference': 'RIZMM25',
    'designation': 'RIZ MM 25KG',
    'store_id': 1,
    'quantity': 100,
  });
  await db.insert('stock_outputs', {
    'date': '2026-02-03',
    'reference': 'RIZMM25',
    'designation': 'RIZ MM 25KG',
    'invoice_number': 'FA-77',
    'store_id': 1,
    'destination': 'Client Est',
    'quantity': 25,
  });
  await db.insert('company_settings', {'id': 1, 'name': 'SOCOGEN Sarl'});
  return db;
}

/// Monte la base par le chemin de l'application, pas par une copie de
/// ses étapes : c'est l'ordre réel qu'on veut vérifier.
Future<void> _migrer(Database db) async =>
    DatabaseService.migrer(db, 3);

void main() {
  late Database db;

  setUp(() async => db = await _ouvrirV3AvecDonnees());
  tearDown(() async => db.close());

  group('rien ne se perd', () {
    test('les articles, stocks et mouvements traversent la migration', () async {
      await _migrer(db);

      final articles = await db.query('products');
      expect(articles, hasLength(1));
      expect(articles.first['reference'], 'RIZMM25');
      expect(articles.first['designation'], 'RIZ MM 25KG');

      expect(await db.query('product_stocks'), hasLength(1));
      expect(await db.query('stock_entries'), hasLength(1));
      expect(await db.query('stock_outputs'), hasLength(1));
      expect(
        (await db.query('company_settings')).first['name'],
        'SOCOGEN Sarl',
      );
    });

    test('un article existant devient actif, pas inactif', () async {
      await _migrer(db);

      final article = Product.fromMap((await db.query('products')).first);
      expect(
        article.actif,
        isTrue,
        reason: "un article déjà en base n'a jamais été autre chose qu'actif",
      );
    });
  });

  group('les prix arrivent inconnus, pas à zéro', () {
    test('un article migré n\'a ni prix de vente ni prix d\'achat', () async {
      await _migrer(db);

      final article = Product.fromMap((await db.query('products')).first);
      expect(article.prixVenteUnites, isNull);
      expect(article.prixAchatUnites, isNull);
      expect(
        article.estTarife,
        isFalse,
        reason: 'un article sans prix ne doit pas être vendable en caisse',
      );
    });

    test('zéro et inconnu ne se confondent pas', () async {
      await _migrer(db);
      await db.insert('products', {
        'reference': 'ECHANTILLON',
        'designation': 'Échantillon gratuit',
        'prix_vente': 0,
      });

      final gratuit = Product.fromMap(
        (await db.query('products',
                where: 'reference = ?', whereArgs: ['ECHANTILLON']))
            .first,
      );
      // Un article réellement gratuit est tarifé à zéro et reste
      // vendable ; un article sans prix ne l'est pas.
      expect(gratuit.prixVenteUnites, 0);
      expect(gratuit.estTarife, isTrue);
    });
  });

  group('les taux de TVA', () {
    test('le Cameroun arrive avec son taux normal et son exonération', () async {
      await _migrer(db);

      final taux = await db.query('taux_tva', orderBy: 'pour_dix_mille');
      expect(taux, hasLength(2));
      expect(taux.first['code'], 'EXONERE');
      expect(taux.first['pour_dix_mille'], 0);
      expect(taux.last['code'], 'NORMAL');
      expect(taux.last['pour_dix_mille'], 1925);
    });

    test('un seul taux est marqué par défaut', () async {
      await _migrer(db);

      final defauts =
          await db.query('taux_tva', where: 'is_defaut = 1');
      expect(defauts, hasLength(1));
      expect(defauts.first['code'], 'NORMAL');
    });

    test('rejouer la migration ne duplique pas les taux', () async {
      // Une migration doit pouvoir repasser sans rien casser : un
      // appareil interrompu au mauvais moment la rejouera.
      await _migrer(db);
      for (final sql in AppSchema.tauxTvaParDefaut) {
        await db.execute(sql);
      }

      expect(await db.query('taux_tva'), hasLength(2));
    });
  });

  group('la devise', () {
    test('une société existante repart en francs CFA', () async {
      await _migrer(db);

      final societe = (await db.query('company_settings')).first;
      expect(societe['devise'], 'XAF');
    });
  });

  group('convergence des deux chemins', () {
    test('une base neuve et une base migrée ont les mêmes colonnes', () async {
      // Une installation neuve part du seed en v1 et monte par les
      // migrations ; le repli sans seed crée directement la v4. Si les
      // deux divergent, un bug n'apparaît que sur l'un des deux chemins.
      await _migrer(db);
      final migree = await db.rawQuery('PRAGMA table_info(products)');

      final neuve = await databaseFactoryFfi.openDatabase(
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
      final colonnesNeuves = await neuve.rawQuery('PRAGMA table_info(products)');
      await neuve.close();

      String noms(List<Map<String, Object?>> colonnes) =>
          (colonnes.map((c) => c['name'] as String).toList()..sort()).join(',');

      expect(noms(migree), noms(colonnesNeuves));
    });
  });

  group('la chaîne, dans son ordre', () {
    test('une base en v3 reçoit tous les index, ceux de la v5 compris',
        () async {
      // Le défaut que ceci empêche : chaque étape réappliquait la liste
      // complète des index, donc `_migrateToV4` — qui tourne sur une
      // base encore en v3 — tentait un index sur `tiers`, table que
      // seule la v5 apporte. La migration levait, et l'application
      // n'ouvrait plus sa base du tout. Une base à jour ne voyait rien :
      // il fallait venir de loin pour tomber dessus.
      await DatabaseService.migrer(db, 3);

      final index = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index'"))
          .map((r) => r['name'])
          .toSet();
      expect(index, containsAll(['idx_tiers_nom', 'idx_products_famille']));
    });

    test("remonter deux versions d'un coup aboutit au même schéma", () async {
      await DatabaseService.migrer(db, 3);

      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'])
          .toSet();
      expect(tables, containsAll(['familles', 'taux_tva', 'tiers']));
    });
  });

  group("installation neuve : le seed en v1 monte jusqu'au schéma courant", () {
    test('toute la chaîne de migrations passe sur le schéma livré', () async {
      // C'est le parcours de chaque nouveau client : la base livrée est
      // en v1 et grimpe par migrations successives. Il ne se distingue
      // du parcours d'une mise à jour que par le nombre d'étapes, ce qui
      // suffit à faire diverger les deux si personne ne regarde.
      final schemaLivre = File('../scripts/schema.sql');
      expect(
        schemaLivre.existsSync(),
        isTrue,
        reason: 'scripts/schema.sql est la source de la base livrée',
      );

      final neuve = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, singleInstance: false),
      );
      // Les commentaires se retirent ligne à ligne : découper sur « ; »
      // laisse le commentaire qui précède une instruction collé devant
      // elle, et jeter le morceau entier ferait disparaître la table.
      final sansCommentaires = schemaLivre
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      for (final sql in sansCommentaires
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)) {
        await neuve.execute(sql);
      }

      await DatabaseService.migrer(neuve, 1);

      final colonnes = (await neuve.rawQuery('PRAGMA table_info(products)'))
          .map((c) => c['name'] as String)
          .toSet();
      expect(
        colonnes,
        containsAll(['prix_vente', 'prix_achat', 'tva_id', 'famille_id',
            'code_barre', 'actif']),
      );
      expect(await neuve.query('taux_tva'), hasLength(2));
      await neuve.close();
    });
  });

}
