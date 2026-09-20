import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/shared/models/view_models.dart';

class TransactionRepository {
  TransactionRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// Combined entries+outputs, oldest first, each annotated with the
  /// stock the product stood at once that movement was applied.
  ///
  /// The balance is kept per product, starting from that product's
  /// `product_stocks.initial_stock`, so a report covering the whole
  /// catalogue reads as a stock card per product rather than as one
  /// running total across unrelated articles.
  ///
  /// [storeId] narrows what "stock" means: with a store selected the
  /// balance is that store's stock, otherwise it is the product's stock
  /// across every store.
  ///
  /// [dateFrom], [dateTo], [type] and [search] choose which rows are
  /// *shown*. They deliberately do not enter the balance: the stock after
  /// a movement is a fact about that movement, not about the filter, so
  /// the figures stay right when the operator looks at February alone or
  /// at outputs alone.
  Future<List<TransactionRow>> getTransactions({
    String? reference,
    String? search,
    int? storeId,
    TransactionType? type,
    String? dateFrom,
    String? dateTo,
  }) async {
    final db = await _db;

    // --- Scope: which products and which store the figures cover.
    final scopeWhere = <String>[];
    final scopeArgs = <Object?>[];
    if (reference != null) {
      scopeWhere.add('reference = ?');
      scopeArgs.add(reference);
    }
    if (storeId != null) {
      scopeWhere.add('store_id = ?');
      scopeArgs.add(storeId);
    }

    final openingStock = await _openingStock(db, reference, storeId);
    final rows = await _movements(db, scopeWhere, scopeArgs, storeId);

    // Chronological order (entries before outputs on the same date, then
    // by id) so the running balance is deterministic.
    rows.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byType = a.type.index.compareTo(b.type.index);
      if (byType != 0) return byType;
      return a.id.compareTo(b.id);
    });

    final balances = <String, int>{};
    for (final row in rows) {
      final running =
          balances[row.reference] ?? openingStock[row.reference] ?? 0;
      final next = running + row.inQty - row.outQty;
      balances[row.reference] = next;
      row.balance = next;
    }

    return _applyDisplayFilters(rows, search, type, dateFrom, dateTo);
  }

  /// Opening stock per product reference, over the same store scope as
  /// the movements.
  Future<Map<String, int>> _openingStock(
    Database db,
    String? reference,
    int? storeId,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    if (reference != null) {
      where.add('p.reference = ?');
      args.add(reference);
    }
    if (storeId != null) {
      where.add('ps.store_id = ?');
      args.add(storeId);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT p.reference AS reference,
             COALESCE(SUM(ps.initial_stock), 0) AS opening
      FROM product_stocks ps
      JOIN products p ON p.id = ps.product_id
      $whereSql
      GROUP BY p.reference
    ''', args);

    return {
      for (final row in rows)
        row['reference'] as String: (row['opening'] as num).toInt(),
    };
  }

  Future<List<TransactionRow>> _movements(
    Database db,
    List<String> scopeWhere,
    List<Object?> scopeArgs,
    int? storeId,
  ) async {
    final whereSql =
        scopeWhere.isEmpty ? '' : 'WHERE ${scopeWhere.map((c) => 'se.$c').join(' AND ')}';
    final outWhereSql =
        scopeWhere.isEmpty ? '' : 'WHERE ${scopeWhere.map((c) => 'so.$c').join(' AND ')}';

    final rows = <TransactionRow>[];

    final entryRows = await db.rawQuery('''
      SELECT se.id, se.date, se.reference, se.designation, se.supplier,
             se.quantity, se.tiers_id, s.name AS store_name,
             COALESCE(p.stock_min, c.stock_min_defaut, ?) AS stock_min
      FROM stock_entries se
      JOIN stores s ON s.id = se.store_id
      -- Par la référence, pas par une clé étrangère : c'est ainsi qu'un
      -- mouvement retrouve son article ici, et un article supprimé
      -- laisse ses lignes derrière lui. LEFT, donc, et le COALESCE
      -- retombe sur le seuil d'entreprise.
      LEFT JOIN products p ON p.reference = se.reference
      LEFT JOIN company_settings c ON c.id = 1
      $whereSql
    ''', [StockStatus.seuilParDefaut, ...scopeArgs]);
    for (final row in entryRows) {
      rows.add(TransactionRow(
        type: TransactionType.entry,
        id: row['id'] as int,
        date: row['date'] as String,
        reference: row['reference'] as String,
        designation: row['designation'] as String,
        storeName: row['store_name'] as String,
        partner: (row['supplier'] as String?) ?? '',
        tiersId: row['tiers_id'] as int?,
        stockMin: (row['stock_min'] as num).toInt(),
        invoiceNumber: '',
        inQty: (row['quantity'] as num).toInt(),
        outQty: 0,
      ));
    }

    final outputRows = await db.rawQuery('''
      SELECT so.id, so.date, so.reference, so.designation, so.destination,
             so.invoice_number, so.quantity, so.tiers_id, s.name AS store_name,
             COALESCE(p.stock_min, c.stock_min_defaut, ?) AS stock_min
      FROM stock_outputs so
      JOIN stores s ON s.id = so.store_id
      LEFT JOIN products p ON p.reference = so.reference
      LEFT JOIN company_settings c ON c.id = 1
      $outWhereSql
    ''', [StockStatus.seuilParDefaut, ...scopeArgs]);
    for (final row in outputRows) {
      rows.add(TransactionRow(
        type: TransactionType.output,
        id: row['id'] as int,
        date: row['date'] as String,
        reference: row['reference'] as String,
        designation: row['designation'] as String,
        storeName: row['store_name'] as String,
        partner: (row['destination'] as String?) ?? '',
        tiersId: row['tiers_id'] as int?,
        stockMin: (row['stock_min'] as num).toInt(),
        invoiceNumber: (row['invoice_number'] as String?) ?? '',
        inQty: 0,
        outQty: (row['quantity'] as num).toInt(),
      ));
    }

    return rows;
  }

  List<TransactionRow> _applyDisplayFilters(
    List<TransactionRow> rows,
    String? search,
    TransactionType? type,
    String? dateFrom,
    String? dateTo,
  ) {
    final needle = search?.trim().toLowerCase();
    return rows.where((row) {
      if (type != null && row.type != type) return false;
      if (dateFrom != null && row.date.compareTo(dateFrom) < 0) return false;
      if (dateTo != null && row.date.compareTo(dateTo) > 0) return false;
      if (needle != null && needle.isNotEmpty) {
        final matches = row.reference.toLowerCase().contains(needle) ||
            row.designation.toLowerCase().contains(needle);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }
}
