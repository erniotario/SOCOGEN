import 'package:sqflite/sqflite.dart';

import '../db/database_service.dart';
import '../models/view_models.dart';

class ReportRepository {
  ReportRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// One row per (product x store), with entries/outputs scoped to that
  /// store and matched to the product by `reference`.
  Future<List<ReportRow>> getReportRows({
    String? search,
    int? storeId,
    StockStatus? status,
  }) async {
    final db = await _db;

    final whereClauses = <String>[];
    final args = <Object?>[];
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      whereClauses.add('(p.reference LIKE ? OR p.designation LIKE ?)');
      args.addAll([like, like]);
    }
    if (storeId != null) {
      whereClauses.add('s.id = ?');
      args.add(storeId);
    }
    final where = whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT
        p.id AS product_id,
        p.reference AS reference,
        p.designation AS designation,
        p.unit AS unit,
        s.id AS store_id,
        s.name AS store_name,
        ps.initial_stock AS initial_stock,
        COALESCE((SELECT SUM(quantity) FROM stock_entries se WHERE se.reference = p.reference AND se.store_id = s.id), 0) AS entries,
        COALESCE((SELECT SUM(quantity) FROM stock_outputs so WHERE so.reference = p.reference AND so.store_id = s.id), 0) AS outputs
      FROM product_stocks ps
      JOIN products p ON p.id = ps.product_id
      JOIN stores s ON s.id = ps.store_id
      $where
      ORDER BY p.reference, s.name
    ''', args);

    var result = rows
        .map((row) => ReportRow(
              productId: row['product_id'] as int,
              reference: row['reference'] as String,
              designation: row['designation'] as String,
              unit: (row['unit'] as String?) ?? 'unité',
              storeId: row['store_id'] as int,
              storeName: row['store_name'] as String,
              initialStock: row['initial_stock'] as int,
              entries: row['entries'] as int,
              outputs: row['outputs'] as int,
            ))
        .toList();

    if (status != null) {
      result = result.where((r) => r.status == status).toList();
    }
    return result;
  }

  /// KPI counts computed over the FULL unfiltered dataset.
  Future<({int total, int enStock, int stockFaible, int rupture})> getStatusCounts() async {
    final rows = await getReportRows();
    var enStock = 0, stockFaible = 0, rupture = 0;
    for (final row in rows) {
      switch (row.status) {
        case StockStatus.enStock:
          enStock++;
          break;
        case StockStatus.stockFaible:
          stockFaible++;
          break;
        case StockStatus.rupture:
          rupture++;
          break;
      }
    }
    return (total: rows.length, enStock: enStock, stockFaible: stockFaible, rupture: rupture);
  }
}
