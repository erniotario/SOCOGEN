import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/shared/models/view_models.dart';

/// Les soldes de stock.
///
/// Ces deux calculs vivaient dans `ProductRepository`, par accident
/// d'histoire : ils prennent une référence d'article, donc ils avaient
/// atterri à côté des articles. Ils n'interrogent pourtant que des
/// tables de stock — `product_stocks`, `stock_entries`, `stock_outputs`
/// — et c'est le module stock qui répond de leur exactitude. Les laisser
/// dans le catalogue obligeait tout le module stock à venir y puiser.
///
/// Le stock courant reste dérivé, jamais stocké :
/// `initial_stock + entrées − sorties`.
class StockRepository {
  StockRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Solde de (référence, magasin) en laissant délibérément un mouvement
  /// hors de la somme.
  ///
  /// Modifier un mouvement passé doit se juger sur ce que la
  /// modification *laisserait derrière elle*, pas sur ce que dit le
  /// registre pendant que l'ancien chiffre de la ligne y compte encore —
  /// sans quoi faire passer une sortie de 5 à 50 paraît anodin jusqu'à
  /// l'enregistrement.
  ///
  /// `id IS NOT ?` porte toute l'exclusion : face à NULL il est vrai pour
  /// chaque ligne (on n'exclut rien), face à un identifiant il est vrai
  /// pour toutes sauf celle-là. La même instruction sert donc au
  /// mouvement neuf comme au mouvement modifié.
  Future<int> balanceExcluding({
    required String reference,
    required int storeId,
    int? excludeEntryId,
    int? excludeOutputId,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE((
          SELECT ps.initial_stock FROM product_stocks ps
          JOIN products p ON p.id = ps.product_id
          WHERE p.reference = ? AND ps.store_id = ?
        ), 0)
        + COALESCE((
          SELECT SUM(quantity) FROM stock_entries
          WHERE reference = ? AND store_id = ? AND id IS NOT ?
        ), 0)
        - COALESCE((
          SELECT SUM(quantity) FROM stock_outputs
          WHERE reference = ? AND store_id = ? AND id IS NOT ?
        ), 0)
        AS balance
    ''', [
      reference, storeId,
      reference, storeId, excludeEntryId,
      reference, storeId, excludeOutputId,
    ]);
    return (rows.first['balance'] as num?)?.toInt() ?? 0;
  }

  /// Stock disponible par magasin pour une référence.
  ///
  /// Ne liste que les magasins où l'article a une ligne de stock : un
  /// magasin qui n'a jamais tenu cet article n'a pas à apparaître comme
  /// étant à zéro.
  Future<List<StoreAvailability>> getStoreAvailability(
    String reference,
    int productId,
  ) async {
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

  // --- lignes de stock par (article, magasin) ---------------------
  // Déplacées depuis ProductRepository : elles écrivent dans
  // product_stocks, qui est une table de stock et non de catalogue.

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
