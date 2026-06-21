import 'package:sqflite/sqflite.dart';

import '../db/database_service.dart';
import '../db/sync_columns.dart';
import '../models/product.dart';
import '../models/product_stock.dart';
import '../models/view_models.dart';

class ProductRepository {
  ProductRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  /// All products with aggregated stock figures, used by the
  /// Dashboard and Produits screens.
  ///
  /// current_stock = initial_stock_total + entries_total - outputs_total
  /// where entries/outputs are summed across ALL stores by `reference`.
  Future<List<ProductOverview>> getProductOverviews({String? search}) async {
    final db = await _db;
    final whereClauses = <String>[];
    final args = <Object?>[];
    if (search != null && search.trim().isNotEmpty) {
      whereClauses.add('(p.reference LIKE ? OR p.designation LIKE ?)');
      final like = '%${search.trim()}%';
      args.addAll([like, like]);
    }
    final where = whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT
        p.id AS id,
        p.reference AS reference,
        p.designation AS designation,
        p.unit AS unit,
        COALESCE(ps_sum.initial_total, 0) AS initial_total,
        COALESCE(e_sum.entries_total, 0) AS entries_total,
        COALESCE(o_sum.outputs_total, 0) AS outputs_total,
        COALESCE(stores_sum.store_names, '') AS store_names,
        COALESCE(ps_sum.stock_count, 0) AS stock_count,
        first_ps.id AS first_stock_id,
        first_ps.store_id AS first_store_id,
        COALESCE(first_ps.initial_stock, 0) AS first_initial_stock
      FROM products p
      LEFT JOIN (
        SELECT product_id, SUM(initial_stock) AS initial_total, COUNT(*) AS stock_count
        FROM product_stocks GROUP BY product_id
      ) ps_sum ON ps_sum.product_id = p.id
      LEFT JOIN (
        SELECT reference, SUM(quantity) AS entries_total
        FROM stock_entries GROUP BY reference
      ) e_sum ON e_sum.reference = p.reference
      LEFT JOIN (
        SELECT reference, SUM(quantity) AS outputs_total
        FROM stock_outputs GROUP BY reference
      ) o_sum ON o_sum.reference = p.reference
      LEFT JOIN (
        SELECT product_id, GROUP_CONCAT(name, ' / ') AS store_names
        FROM (
          SELECT ps.product_id AS product_id, s.name AS name
          FROM product_stocks ps
          JOIN stores s ON s.id = ps.store_id
          ORDER BY s.name
        )
        GROUP BY product_id
      ) stores_sum ON stores_sum.product_id = p.id
      LEFT JOIN product_stocks first_ps ON first_ps.id = (
        SELECT id FROM product_stocks WHERE product_id = p.id ORDER BY id LIMIT 1
      )
      $where
      ORDER BY p.reference
    ''', args);

    return rows
        .map((row) => ProductOverview(
              product: Product(
                id: row['id'] as int,
                reference: row['reference'] as String,
                designation: row['designation'] as String,
                unit: (row['unit'] as String?) ?? 'unité',
              ),
              initialStock: row['initial_total'] as int,
              entriesTotal: row['entries_total'] as int,
              outputsTotal: row['outputs_total'] as int,
              storeNames: row['store_names'] as String,
              stockCount: row['stock_count'] as int,
              firstStockId: row['first_stock_id'] as int?,
              firstStoreId: row['first_store_id'] as int?,
              firstStoreInitialStock: row['first_initial_stock'] as int,
            ))
        .toList();
  }

  /// True if any stock_entries or stock_outputs rows reference this
  /// product's `reference` (used to warn before deleting a product).
  Future<bool> hasMovements(String reference) async {
    final db = await _db;
    final entries = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_entries WHERE reference = ?',
          [reference],
        )) ??
        0;
    if (entries > 0) return true;
    final outputs = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_outputs WHERE reference = ?',
          [reference],
        )) ??
        0;
    return outputs > 0;
  }

  Future<Product?> getByReference(String reference) async {
    final db = await _db;
    final rows = await db.query(
      'products',
      where: 'reference = ?',
      whereArgs: [reference],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<bool> referenceExists(String reference, {int? excludeId}) async {
    final db = await _db;
    final rows = excludeId == null
        ? await db.query('products', where: 'reference = ?', whereArgs: [reference])
        : await db.query(
            'products',
            where: 'reference = ? AND id != ?',
            whereArgs: [reference, excludeId],
          );
    return rows.isNotEmpty;
  }

  /// Per-store stock rows for a product, joined with store names.
  /// The first row is treated as the product's "primary" store
  /// (used to pre-select a store on the Entrées form).
  Future<List<({ProductStock stock, String storeName})>> getProductStocks(
    int productId,
  ) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT ps.id, ps.product_id, ps.store_id, ps.initial_stock, s.name AS store_name
      FROM product_stocks ps
      JOIN stores s ON s.id = ps.store_id
      WHERE ps.product_id = ?
      ORDER BY ps.id
    ''', [productId]);
    return rows
        .map((row) => (
              stock: ProductStock.fromMap(row),
              storeName: row['store_name'] as String,
            ))
        .toList();
  }

  /// Available stock per store for a given product reference:
  /// initial_stock(product, store) + entries(reference, store) - outputs(reference, store).
  /// Only includes stores the product has a product_stocks row in.
  Future<List<StoreAvailability>> getStoreAvailability(String reference, int productId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        s.id AS store_id,
        s.name AS store_name,
        ps.initial_stock AS initial_stock,
        ps.initial_stock
          + COALESCE((SELECT SUM(quantity) FROM stock_entries se WHERE se.reference = ? AND se.store_id = s.id), 0)
          - COALESCE((SELECT SUM(quantity) FROM stock_outputs so WHERE so.reference = ? AND so.store_id = s.id), 0)
          AS available
      FROM product_stocks ps
      JOIN stores s ON s.id = ps.store_id
      WHERE ps.product_id = ?
      ORDER BY ps.id
    ''', [reference, reference, productId]);
    return rows
        .map((row) => StoreAvailability(
              storeId: row['store_id'] as int,
              storeName: row['store_name'] as String,
              initialStock: row['initial_stock'] as int,
              available: row['available'] as int,
            ))
        .toList();
  }

  Future<int> createProduct({
    required String reference,
    required String designation,
    required String unit,
  }) async {
    final db = await _db;
    return db.insert('products', {
      'reference': reference,
      'designation': designation,
      'unit': unit,
      'updated_at': nowIso(),
    });
  }

  Future<void> updateProduct(Product product) async {
    final db = await _db;
    final values = product.toMap(includeId: false);
    values['updated_at'] = nowIso();
    await db.update(
      'products',
      values,
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  /// Deletes a product and (via ON DELETE CASCADE) its product_stocks rows.
  /// stock_entries/stock_outputs are kept (they reference by `reference`,
  /// not by id), matching the Python app's behaviour.
  Future<void> deleteProduct(int productId) async {
    final db = await _db;
    final rows = await db.query('products', columns: ['reference'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isNotEmpty) {
      await recordTombstone(db, 'products', rows.first['reference'] as String);
    }
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
  }

  Future<void> deleteProductStock(int productStockId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.reference AS product_reference, s.name AS store_name
      FROM product_stocks ps
      JOIN products p ON p.id = ps.product_id
      JOIN stores s ON s.id = ps.store_id
      WHERE ps.id = ?
    ''', [productStockId]);
    if (rows.isNotEmpty) {
      final mergeKey = '${rows.first['product_reference']}|${rows.first['store_name']}';
      await recordTombstone(db, 'product_stocks', mergeKey);
    }
    await db.delete('product_stocks', where: 'id = ?', whereArgs: [productStockId]);
  }

  /// Updates an existing product_stocks row's store and initial stock,
  /// e.g. when editing a product moves it to a different store.
  Future<void> updateProductStock(
    int productStockId, {
    required int storeId,
    required int initialStock,
  }) async {
    final db = await _db;
    await db.update(
      'product_stocks',
      {'store_id': storeId, 'initial_stock': initialStock, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [productStockId],
    );
  }

  /// True if a product_stocks row already exists for (productId, storeId).
  /// Used by the Excel import to skip duplicates rather than overwrite
  /// an existing initial stock value.
  Future<bool> productStockExists(int productId, int storeId) async {
    final db = await _db;
    final rows = await db.query(
      'product_stocks',
      where: 'product_id = ? AND store_id = ?',
      whereArgs: [productId, storeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts or updates the product_stocks row for (productId, storeId),
  /// preserving the row id on update.
  Future<void> upsertProductStock({
    required int productId,
    required int storeId,
    required int initialStock,
  }) async {
    final db = await _db;
    final existing = await db.query(
      'product_stocks',
      where: 'product_id = ? AND store_id = ?',
      whereArgs: [productId, storeId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('product_stocks', {
        'product_id': productId,
        'store_id': storeId,
        'initial_stock': initialStock,
        'updated_at': nowIso(),
      });
    } else {
      await db.update(
        'product_stocks',
        {'initial_stock': initialStock, 'updated_at': nowIso()},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }
}
