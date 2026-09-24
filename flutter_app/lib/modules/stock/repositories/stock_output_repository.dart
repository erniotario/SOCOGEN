import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/db/verrou_comptable.dart';
import 'package:erp/modules/stock/models/stock_output.dart';

typedef StockOutputWithStore = ({StockOutput output, String storeName});

class StockOutputRepository {
  StockOutputRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// All outputs, newest first, with the store name joined in.
  Future<List<StockOutputWithStore>> getAll() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT so.id, so.date, so.reference, so.designation, so.invoice_number,
             so.store_id, so.destination, so.quantity, so.tiers_id,
             s.name AS store_name
      FROM stock_outputs so
      JOIN stores s ON s.id = so.store_id
      ORDER BY so.date DESC, so.id DESC
    ''');
    return rows
        .map((row) => (
              output: StockOutput.fromMap(row),
              storeName: row['store_name'] as String,
            ))
        .toList();
  }

  Future<int> create(StockOutput output) async {
    final db = await _db;
    await _verifierPeriode(db, 'stock_outputs', null, output.date, 'la sortie');
    final values = output.toMap(includeId: false);
    values['sync_id'] = newSyncId();
    values['updated_at'] = nowIso();
    // L'auteur se pose ici, jamais par l'appelant : une écriture est
    // signée de qui est connecté, pas de qui le demande.
    values.addAll(attribution());
    return db.insert('stock_outputs', values);
  }

  Future<void> update(StockOutput output) async {
    final db = await _db;
    await _verifierPeriode(
        db, 'stock_outputs', output.id, output.date, 'la correction de la sortie');
    final values = output.toMap(includeId: false);
    values['updated_at'] = nowIso();
    await db.update(
      'stock_outputs',
      values,
      where: 'id = ?',
      whereArgs: [output.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await _verifierPeriode(
        db, 'stock_outputs', id, null, 'la suppression de la sortie');
    final rows = await db.query('stock_outputs', columns: ['sync_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.first['sync_id'] != null) {
      await recordTombstone(db, 'stock_outputs', rows.first['sync_id'] as String);
    }
    await db.delete('stock_outputs', where: 'id = ?', whereArgs: [id]);
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

  /// Sum of `quantity` across ALL outputs (used for the Dashboard KPI).
  Future<int> getTotalQuantity() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COALESCE(SUM(quantity), 0) FROM stock_outputs'),
        ) ??
        0;
  }
}
