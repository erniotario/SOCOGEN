import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/shared/models/view_models.dart';

class ReportRepository {
  ReportRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// Entries and outputs summed once per (reference, store), joined in
  /// rather than looked up per row.
  ///
  /// The correlated-subquery form this replaces re-scanned both movement
  /// tables for every product/store pair, so the report grew with the
  /// product of the two — slow enough on a real catalogue to look like a
  /// freeze.
  static const String _movementTotals = '''
    LEFT JOIN (
      SELECT reference, store_id, SUM(quantity) AS total
      FROM stock_entries GROUP BY reference, store_id
    ) e ON e.reference = p.reference AND e.store_id = s.id
    LEFT JOIN (
      SELECT reference, store_id, SUM(quantity) AS total
      FROM stock_outputs GROUP BY reference, store_id
    ) o ON o.reference = p.reference AND o.store_id = s.id
  ''';

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
        COALESCE(ps.initial_stock, 0) AS initial_stock,
        COALESCE(e.total, 0) AS entries,
        COALESCE(o.total, 0) AS outputs,
        COALESCE(p.stock_min, c.stock_min_defaut, ?) AS stock_min
      FROM product_stocks ps
      JOIN products p ON p.id = ps.product_id
      JOIN stores s ON s.id = ps.store_id
      LEFT JOIN company_settings c ON c.id = 1
      $_movementTotals
      $where
      ORDER BY p.reference, s.name
    ''', [StockStatus.seuilParDefaut, ...args]);

    var result = rows
        .map((row) => ReportRow(
              productId: row['product_id'] as int,
              reference: row['reference'] as String,
              designation: row['designation'] as String,
              unit: (row['unit'] as String?) ?? 'unité',
              storeId: row['store_id'] as int,
              storeName: row['store_name'] as String,
              initialStock: (row['initial_stock'] as num).toInt(),
              entries: (row['entries'] as num).toInt(),
              outputs: (row['outputs'] as num).toInt(),
              stockMin: (row['stock_min'] as num).toInt(),
            ))
        .toList();

    if (status != null) {
      result = result.where((r) => r.status == status).toList();
    }
    return result;
  }

  /// KPI counts computed over the FULL unfiltered dataset.
  ///
  /// Counted in SQL rather than by walking [getReportRows] a second time,
  /// which ran the whole report twice on every load and every keystroke
  /// in the search box.
  Future<({int total, int enStock, int stockFaible, int rupture, int negatif})>
      getStatusCounts() async {
    final db = await _db;

    // Reprend StockStatus.pour : < 0 negatif, 0 rupture, sous le seuil
    // faible, sinon en stock. Le seuil se resout ici exactement comme
    // dans getReportRows -- l'article d'abord, l'entreprise ensuite --
    // parce que l'ecran lit son badge en Dart et son compteur ici, et
    // que les deux ne doivent pas juger la meme ligne differemment.
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN current >= seuil THEN 1 ELSE 0 END) AS en_stock,
        SUM(CASE WHEN current > 0 AND current < seuil THEN 1 ELSE 0 END)
          AS faible,
        SUM(CASE WHEN current = 0 THEN 1 ELSE 0 END) AS rupture,
        SUM(CASE WHEN current < 0 THEN 1 ELSE 0 END) AS negatif
      FROM (
        SELECT
          COALESCE(ps.initial_stock, 0) + COALESCE(e.total, 0) - COALESCE(o.total, 0)
            AS current,
          COALESCE(p.stock_min, c.stock_min_defaut, ?) AS seuil
        FROM product_stocks ps
        JOIN products p ON p.id = ps.product_id
        JOIN stores s ON s.id = ps.store_id
        LEFT JOIN company_settings c ON c.id = 1
        $_movementTotals
      )
    ''', [StockStatus.seuilParDefaut]);

    int at(String column) => (rows.first[column] as num?)?.toInt() ?? 0;
    return (
      total: at('total'),
      enStock: at('en_stock'),
      stockFaible: at('faible'),
      rupture: at('rupture'),
      negatif: at('negatif'),
    );
  }
}
