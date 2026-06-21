import 'package:sqflite/sqflite.dart';

import '../db/database_service.dart';
import '../db/sync_columns.dart';
import '../models/store.dart';
import '../models/view_models.dart';

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

  Future<void> deleteStore(int id) async {
    final db = await _db;
    final rows = await db.query('stores', columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      await recordTombstone(db, 'stores', rows.first['name'] as String);
    }
    await db.delete('stores', where: 'id = ?', whereArgs: [id]);
  }
}
