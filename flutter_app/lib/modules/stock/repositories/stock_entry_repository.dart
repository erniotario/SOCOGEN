import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/db/verrou_comptable.dart';
import 'package:erp/modules/stock/models/stock_entry.dart';

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
             se.store_id, se.quantity, se.tiers_id, s.name AS store_name
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
    await _verifierPeriode(db, 'stock_entries', null, entry.date, "l’entrée");
    final values = entry.toMap(includeId: false);
    values['sync_id'] = newSyncId();
    values['updated_at'] = nowIso();
    // L'auteur se pose ici, jamais par l'appelant : une écriture est
    // signée de qui est connecté, pas de qui le demande.
    values.addAll(attribution());
    return db.insert('stock_entries', values);
  }

  Future<void> update(StockEntry entry) async {
    final db = await _db;
    await _verifierPeriode(
        db, 'stock_entries', entry.id, entry.date, "la correction de l’entrée");
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
    await _verifierPeriode(
        db, 'stock_entries', id, null, "la suppression de l’entrée");
    final rows = await db.query('stock_entries', columns: ['sync_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.first['sync_id'] != null) {
      await recordTombstone(db, 'stock_entries', rows.first['sync_id'] as String);
    }
    await db.delete('stock_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Refuse de toucher à une période fermée.
  ///
  /// Sur une modification, **les deux dates** sont vérifiées : celle
  /// qui est en base et celle qu'on veut poser. Sans la première, on
  /// sortirait une ligne d'une période déclarée en la redatant ; sans
  /// la seconde, on en ferait entrer une.
  Future<void> _verifierPeriode(
    Database db,
    String table,
    int? id,
    String? nouvelleDate,
    String operation,
  ) async {
    VerrouComptable.instance.verifier(nouvelleDate, operation: operation);
    if (id == null) return;
    final rows = await db.query(table,
        columns: ['date'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    VerrouComptable.instance
        .verifier(rows.first['date'] as String?, operation: operation);
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
