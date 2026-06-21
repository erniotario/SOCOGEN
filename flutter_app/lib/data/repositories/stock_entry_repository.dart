import 'package:sqflite/sqflite.dart';

import '../db/database_service.dart';
import '../db/sync_columns.dart';
import '../models/stock_entry.dart';

typedef StockEntryWithStore = ({StockEntry entry, String storeName});

class StockEntryRepository {
  StockEntryRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// All entries, newest first, with the store name joined in.
  Future<List<StockEntryWithStore>> getAll() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT se.id, se.date, se.supplier, se.reference, se.designation,
             se.store_id, se.quantity, s.name AS store_name
      FROM stock_entries se
      JOIN stores s ON s.id = se.store_id
      ORDER BY se.date DESC, se.id DESC
    ''');
    return rows
        .map((row) => (
              entry: StockEntry.fromMap(row),
              storeName: row['store_name'] as String,
            ))
        .toList();
  }

  Future<int> create(StockEntry entry) async {
    final db = await _db;
    final values = entry.toMap(includeId: false);
    values['sync_id'] = newSyncId();
    values['updated_at'] = nowIso();
    return db.insert('stock_entries', values);
  }

  Future<void> update(StockEntry entry) async {
    final db = await _db;
    final values = entry.toMap(includeId: false);
    values['updated_at'] = nowIso();
    await db.update(
      'stock_entries',
      values,
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _db;
    final rows = await db.query('stock_entries', columns: ['sync_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.first['sync_id'] != null) {
      await recordTombstone(db, 'stock_entries', rows.first['sync_id'] as String);
    }
    await db.delete('stock_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Sum of `quantity` across ALL entries (used for the Dashboard KPI).
  Future<int> getTotalQuantity() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COALESCE(SUM(quantity), 0) FROM stock_entries'),
        ) ??
        0;
  }
}
