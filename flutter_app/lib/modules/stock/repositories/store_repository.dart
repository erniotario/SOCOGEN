import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/core/db/sync_columns.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';

class StoreRepository {
  StoreRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  Future<List<Store>> getAllStores() async {
    final db = await _db;
    final rows = await db.query('stores', orderBy: 'name');
    return rows.map(Store.fromMap).toList();
  }

  /// One row per store with product count and total available stock
  /// (initial_stock + entries - outputs, all scoped to that store).
  Future<List<StoreOverview>> getStoreOverview() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        s.id AS id,
        s.name AS name,
        (SELECT COUNT(*) FROM product_stocks ps WHERE ps.store_id = s.id) AS product_count,
        COALESCE((SELECT SUM(initial_stock) FROM product_stocks ps WHERE ps.store_id = s.id), 0)
          + COALESCE((SELECT SUM(quantity) FROM stock_entries se WHERE se.store_id = s.id), 0)
          - COALESCE((SELECT SUM(quantity) FROM stock_outputs so WHERE so.store_id = s.id), 0)
          AS total_stock
      FROM stores s
      ORDER BY s.name
    ''');
    return rows
        .map((row) => StoreOverview(
              store: Store(id: row['id'] as int, name: row['name'] as String),
              productCount: row['product_count'] as int,
              totalStock: row['total_stock'] as int,
            ))
        .toList();
  }

  Future<StoreDetails> getStoreDetails(int storeId) async {
    final db = await _db;
    final store = (await db.query('stores', where: 'id = ?', whereArgs: [storeId])).first;

    final productCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM product_stocks WHERE store_id = ?',
          [storeId],
        )) ??
        0;
    final initialSum = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COALESCE(SUM(initial_stock), 0) FROM product_stocks WHERE store_id = ?',
          [storeId],
        )) ??
        0;
    final entriesSum = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COALESCE(SUM(quantity), 0) FROM stock_entries WHERE store_id = ?',
          [storeId],
        )) ??
        0;
    final outputsSum = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COALESCE(SUM(quantity), 0) FROM stock_outputs WHERE store_id = ?',
          [storeId],
        )) ??
        0;

    return StoreDetails(
      store: Store.fromMap(store),
      productCount: productCount,
      totalEntries: entriesSum,
      totalOutputs: outputsSum,
      currentStock: initialSum + entriesSum - outputsSum,
    );
  }

  Future<bool> nameExists(String name, {int? excludeId}) async {
    final db = await _db;
    final rows = excludeId == null
        ? await db.query('stores', where: 'name = ?', whereArgs: [name])
        : await db.query(
            'stores',
            where: 'name = ? AND id != ?',
            whereArgs: [name, excludeId],
          );
    return rows.isNotEmpty;
  }

  Future<int> createStore(String name) async {
    final db = await _db;
    return db.insert('stores', {'name': name, 'updated_at': nowIso()});
  }

  Future<void> updateStore(int id, String name) async {
    final db = await _db;
    await db.update(
      'stores',
      {'name': name, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// True if the store has any product stock, entries or outputs linked
  /// to it (used to warn before deletion).
  Future<bool> hasLinkedData(int storeId) async {
    final db = await _db;
    final ps = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM product_stocks WHERE store_id = ?',
          [storeId],
        )) ??
        0;
    if (ps > 0) return true;
    final entries = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_entries WHERE store_id = ?',
          [storeId],
        )) ??
        0;
    if (entries > 0) return true;
    final outputs = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_outputs WHERE store_id = ?',
          [storeId],
        )) ??
        0;
    return outputs > 0;
  }

  /// Réunit deux magasins qui désignent le même dépôt.
  ///
  /// Le cas qui l'a rendu nécessaire : « Elig-Essono » et
  /// « Ellig-Essono » dans les données réelles. C'est le même entrepôt
  /// écrit deux fois, et c'est plus grave qu'un doublon de fiche tiers —
  /// le stock est dérivé **par magasin**, donc les mouvements d'un même
  /// dépôt se répartissent entre deux soldes qui ne se voient pas. Un
  /// article peut paraître en rupture d'un côté et fourni de l'autre.
  ///
  /// Trois choses à savoir sur ce que fait cette opération.
  ///
  /// Les **stocks d'ouverture s'additionnent** quand les deux magasins
  /// portent le même article : `product_stocks` est unique par
  /// (article, magasin), une simple réaffectation violerait la
  /// contrainte, et l'ouverture du dépôt réuni est bien la somme de ses
  /// deux moitiés.
  ///
  /// Un **transfert entre les deux** magasins reste debout. Il devient
  /// un transfert vers soi-même, ce qui n'a plus de sens comme
  /// opération, mais ses deux mouvements se retrouvent dans le même
  /// magasin et s'y annulent — le solde reste juste, et l'historique
  /// continue de dire ce qui a été fait ce jour-là.
  ///
  /// Le magasin source est **supprimé**, contrairement à une fiche
  /// tiers qu'on désactive. La différence est réelle : une fiche garde
  /// son nom sur les mouvements passés, alors qu'un magasin vidé de ses
  /// mouvements et de ses stocks n'est plus référencé par rien. Le
  /// tombstone part sous son nom, puisque c'est ainsi que la
  /// synchronisation identifie un magasin.
  Future<({int mouvements, int lignesStock, int transferts})> fusionner({
    required int sourceId,
    required int cibleId,
  }) async {
    if (sourceId == cibleId) {
      throw const ErreurUtilisateur(
        'Impossible de fusionner un magasin avec lui-même.',
      );
    }
    final db = await _db;
    final source = await _magasin(db, sourceId);
    final cible = await _magasin(db, cibleId);
    if (source == null || cible == null) {
      throw const ErreurUtilisateur('Magasin introuvable.');
    }

    return db.transaction((txn) async {
      // Les stocks d'ouverture, article par article : additionner là où
      // la cible en a déjà un, réaffecter sinon.
      var lignesStock = 0;
      final aDeplacer = await txn.query('product_stocks',
          where: 'store_id = ?', whereArgs: [sourceId]);
      for (final ligne in aDeplacer) {
        final produitId = ligne['product_id'] as int;
        final ouverture = (ligne['initial_stock'] as num?)?.toInt() ?? 0;
        final existant = await txn.query(
          'product_stocks',
          where: 'store_id = ? AND product_id = ?',
          whereArgs: [cibleId, produitId],
          limit: 1,
        );
        if (existant.isEmpty) {
          await txn.update(
            'product_stocks',
            {'store_id': cibleId, 'updated_at': nowIso()},
            where: 'id = ?',
            whereArgs: [ligne['id']],
          );
        } else {
          final cumul =
              ((existant.first['initial_stock'] as num?)?.toInt() ?? 0) +
                  ouverture;
          await txn.update(
            'product_stocks',
            {'initial_stock': cumul, 'updated_at': nowIso()},
            where: 'id = ?',
            whereArgs: [existant.first['id']],
          );
          await txn.delete('product_stocks',
              where: 'id = ?', whereArgs: [ligne['id']]);
        }
        lignesStock++;
      }

      var mouvements = 0;
      for (final table in ['stock_entries', 'stock_outputs']) {
        mouvements += await txn.update(
          table,
          {'store_id': cibleId, 'updated_at': nowIso()},
          where: 'store_id = ?',
          whereArgs: [sourceId],
        );
      }

      var transferts = await txn.update(
        'transferts',
        {'source_id': cibleId, 'updated_at': nowIso()},
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      transferts += await txn.update(
        'transferts',
        {'destination_id': cibleId, 'updated_at': nowIso()},
        where: 'destination_id = ?',
        whereArgs: [sourceId],
      );

      await recordTombstone(txn, 'stores', source.name);
      await txn.delete('stores', where: 'id = ?', whereArgs: [sourceId]);

      return (
        mouvements: mouvements,
        lignesStock: lignesStock,
        transferts: transferts,
      );
    });
  }

  Future<Store?> _magasin(DatabaseExecutor db, int id) async {
    final rows =
        await db.query('stores', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Store.fromMap(rows.first);
  }

  Future<void> deleteStore(int id) async {
    final db = await _db;
    final rows = await db.query('stores', columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      await recordTombstone(db, 'stores', rows.first['name'] as String);
    }
    await db.delete('stores', where: 'id = ?', whereArgs: [id]);
  }
}
