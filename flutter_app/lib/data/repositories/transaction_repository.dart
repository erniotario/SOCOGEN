import 'package:sqflite/sqflite.dart';

import '../db/database_service.dart';
import '../models/view_models.dart';

class TransactionRepository {
  TransactionRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// Combined entries+outputs, oldest first, each annotated with a running
  /// balance.
  ///
  /// The balance starts at the SUM of `product_stocks.initial_stock` for
  /// [reference] (or 0 when [reference] is null, i.e. "Tous les produits"),
  /// then accumulates `in_qty - out_qty` chronologically (oldest first).
  Future<List<TransactionRow>> getTransactions({
    String? reference,
    String? search,
    int? storeId,
    TransactionType? type,
    String? dateFrom,
    String? dateTo,
  }) async {
    final db = await _db;

    var initialSum = 0;
    if (reference != null) {
      final product = await db.query(
        'products',
        where: 'reference = ?',
        whereArgs: [reference],
        limit: 1,
      );
      if (product.isNotEmpty) {
        if (storeId != null) {
          initialSum = Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COALESCE(initial_stock, 0) FROM product_stocks WHERE product_id = ? AND store_id = ?',
                [product.first['id'], storeId],
              )) ??
              0;
        } else {
          initialSum = Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COALESCE(SUM(initial_stock), 0) FROM product_stocks WHERE product_id = ?',
                [product.first['id']],
              )) ??
              0;
        }
      }
    }

    final entryWhere = <String>[];
    final entryArgs = <Object?>[];
    final outputWhere = <String>[];
    final outputArgs = <Object?>[];

    if (reference != null) {
      entryWhere.add('se.reference = ?');
      entryArgs.add(reference);
      outputWhere.add('so.reference = ?');
      outputArgs.add(reference);
    }
    if (storeId != null) {
      entryWhere.add('se.store_id = ?');
      entryArgs.add(storeId);
      outputWhere.add('so.store_id = ?');
      outputArgs.add(storeId);
    }
    if (dateFrom != null) {
      entryWhere.add('se.date >= ?');
      entryArgs.add(dateFrom);
      outputWhere.add('so.date >= ?');
      outputArgs.add(dateFrom);
    }
    if (dateTo != null) {
      entryWhere.add('se.date <= ?');
      entryArgs.add(dateTo);
      outputWhere.add('so.date <= ?');
      outputArgs.add(dateTo);
    }
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      entryWhere.add('(se.reference LIKE ? OR se.designation LIKE ?)');
      entryArgs.addAll([like, like]);
      outputWhere.add('(so.reference LIKE ? OR so.designation LIKE ?)');
      outputArgs.addAll([like, like]);
    }

    final rows = <TransactionRow>[];

    if (type != TransactionType.output) {
      final whereSql = entryWhere.isEmpty ? '' : 'WHERE ${entryWhere.join(' AND ')}';
      final entryRows = await db.rawQuery('''
        SELECT se.id, se.date, se.reference, se.designation, se.supplier,
               se.quantity, s.name AS store_name
        FROM stock_entries se
        JOIN stores s ON s.id = se.store_id
        $whereSql
      ''', entryArgs);
      for (final row in entryRows) {
        rows.add(TransactionRow(
          type: TransactionType.entry,
          id: row['id'] as int,
          date: row['date'] as String,
          reference: row['reference'] as String,
          designation: row['designation'] as String,
          storeName: row['store_name'] as String,
          partner: (row['supplier'] as String?) ?? '',
          invoiceNumber: '',
          inQty: row['quantity'] as int,
          outQty: 0,
        ));
      }
    }

    if (type != TransactionType.entry) {
      final whereSql = outputWhere.isEmpty ? '' : 'WHERE ${outputWhere.join(' AND ')}';
      final outputRows = await db.rawQuery('''
        SELECT so.id, so.date, so.reference, so.designation, so.destination,
               so.invoice_number, so.quantity, s.name AS store_name
        FROM stock_outputs so
        JOIN stores s ON s.id = so.store_id
        $whereSql
      ''', outputArgs);
      for (final row in outputRows) {
        rows.add(TransactionRow(
          type: TransactionType.output,
          id: row['id'] as int,
          date: row['date'] as String,
          reference: row['reference'] as String,
          designation: row['designation'] as String,
          storeName: row['store_name'] as String,
          partner: (row['destination'] as String?) ?? '',
          invoiceNumber: (row['invoice_number'] as String?) ?? '',
          inQty: 0,
          outQty: row['quantity'] as int,
        ));
      }
    }

    // Chronological order (entries before outputs on the same date) to
    // compute the running balance correctly.
    rows.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.type.index.compareTo(b.type.index);
    });

    var balance = initialSum;
    for (final row in rows) {
      balance += row.inQty - row.outQty;
      row.balance = balance;
    }

    return rows;
  }
}
