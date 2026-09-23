import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/sync_columns.dart';

import 'package:erp/core/sync/sync_models.dart';

/// Sentinel "since" value meaning "the beginning of time", used the first
/// time a device syncs (so every local row is sent).
const String syncEpoch = '1970-01-01T00:00:00.000Z';

/// Collects local changes and applies a peer's changes to the database.
///
/// Merge strategy: `stores`/`products` are matched by their natural unique
/// key (`name`/`reference`), `product_stocks` by `(product reference, store
/// name)`, and `stock_entries`/`stock_outputs` by a generated `sync_id`
/// (they have no natural unique key). For each row, the side with the more
/// recent `updated_at` wins. Deletions are propagated via `sync_tombstones`.
class SyncEngine {
  SyncEngine._();

  /// Identity of the business this database belongs to.
  ///
  /// Held in `sync_meta` rather than a column, because it is a property of
  /// the whole file and not of any row -- a device serves one business, the
  /// way a paper ledger in a back office does.
  ///
  /// Null means *not yet claimed*. A database is deliberately not stamped on
  /// creation: two devices of the same business would then mint different
  /// ids and refuse each other forever. Identity is settled on first sync
  /// instead, by [reconcileTenant].
  static Future<String?> getTenantId(DatabaseExecutor db) async {
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['tenant_id'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Claims this database for [tenantId]. Never overwrites an existing
  /// claim: an identity that could be reassigned would defeat the check it
  /// exists to support.
  static Future<void> claimTenant(DatabaseExecutor db, String tenantId) async {
    final existing = await getTenantId(db);
    if (existing != null) return;
    await db.insert(
      'sync_meta',
      {'key': 'tenant_id', 'value': tenantId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Decides whether two databases may exchange rows, and settles identity
  /// when one or both sides are unclaimed.
  ///
  /// Returns the id both sides should carry. Throws [TenantMismatch] when
  /// the two are claimed by different businesses -- the case this whole
  /// mechanism exists for. `SyncEngine` merges on natural keys (a store by
  /// its name, a product by its reference), so an exchange between two
  /// businesses does not fail: it silently fuses two catalogues, and the
  /// more recent `updated_at` overwrites real stock with a stranger's.
  ///
  /// First contact is trusted. An unclaimed database adopts whoever it
  /// first syncs with, which is the trust already implied by typing a peer's
  /// address into the Sécurité screen. Everything after that is pinned.
  static Future<String> reconcileTenant(
    DatabaseExecutor db,
    String? peerTenantId,
  ) async {
    final local = await getTenantId(db);

    if (local != null && peerTenantId != null && local != peerTenantId) {
      throw const TenantMismatch();
    }
    final settled = local ?? peerTenantId ?? newTenantId();
    if (local == null) await claimTenant(db, settled);
    return settled;
  }

  static Future<String> getLastSyncAt(Database db) async {
    final rows = await db.query('sync_meta', where: 'key = ?', whereArgs: ['last_sync_at'], limit: 1);
    if (rows.isEmpty) return syncEpoch;
    return (rows.first['value'] as String?) ?? syncEpoch;
  }

  static Future<void> setLastSyncAt(Database db, String timestamp) async {
    await db.insert(
      'sync_meta',
      {'key': 'last_sync_at', 'value': timestamp},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Everything changed or deleted strictly after [since].
  static Future<ChangeSet> collectChanges(Database db, String since) async {
    final stores = await db.query('stores', where: 'updated_at > ?', whereArgs: [since]);
    final products = await db.query('products', where: 'updated_at > ?', whereArgs: [since]);

    final productStocks = await db.rawQuery('''
      SELECT p.reference AS product_reference, s.name AS store_name,
             ps.initial_stock, ps.updated_at
      FROM product_stocks ps
      JOIN products p ON p.id = ps.product_id
      JOIN stores s ON s.id = ps.store_id
      WHERE ps.updated_at > ?
    ''', [since]);

    final stockEntries = await db.rawQuery('''
      SELECT se.sync_id, se.date, se.supplier, se.reference, se.designation,
             s.name AS store_name, se.quantity, se.updated_at
      FROM stock_entries se
      JOIN stores s ON s.id = se.store_id
      WHERE se.updated_at > ? AND se.sync_id IS NOT NULL
    ''', [since]);

    final stockOutputs = await db.rawQuery('''
      SELECT so.sync_id, so.date, so.reference, so.designation, so.invoice_number,
             s.name AS store_name, so.destination, so.quantity, so.updated_at
      FROM stock_outputs so
      JOIN stores s ON s.id = so.store_id
      WHERE so.updated_at > ? AND so.sync_id IS NOT NULL
    ''', [since]);

    final tombstoneRows = await db.query('sync_tombstones', where: 'deleted_at > ?', whereArgs: [since]);

    return ChangeSet(
      stores: stores.map((r) => {'name': r['name'], 'updated_at': r['updated_at']}).toList(),
      products: products
          .map((r) => {
                'reference': r['reference'],
                'designation': r['designation'],
                'unit': r['unit'],
                'updated_at': r['updated_at'],
              })
          .toList(),
      productStocks: productStocks,
      stockEntries: stockEntries,
      stockOutputs: stockOutputs,
      tombstones: tombstoneRows
          .map((r) => Tombstone(
                table: r['table_name'] as String,
                mergeKey: r['merge_key'] as String,
                deletedAt: r['deleted_at'] as String,
              ))
          .toList(),
    );
  }

  /// Applies [changes] received from a peer inside a single transaction.
  /// Returns the number of rows actually inserted, updated or deleted.
  static Future<int> applyChanges(Database db, ChangeSet changes) async {
    var applied = 0;
    await db.transaction((txn) async {
      // --- stores ---
      for (final t in changes.tombstones.where((t) => t.table == 'stores')) {
        applied += await txn.delete(
          'stores',
          where: 'name = ? AND (updated_at IS NULL OR updated_at <= ?)',
          whereArgs: [t.mergeKey, t.deletedAt],
        );
      }
      for (final row in changes.stores) {
        applied += await _upsertByKey(
          txn,
          'stores',
          keyColumn: 'name',
          keyValue: row['name'] as String,
          values: row,
        );
      }

      // --- products ---
      for (final t in changes.tombstones.where((t) => t.table == 'products')) {
        applied += await txn.delete(
          'products',
          where: 'reference = ? AND (updated_at IS NULL OR updated_at <= ?)',
          whereArgs: [t.mergeKey, t.deletedAt],
        );
      }
      for (final row in changes.products) {
        applied += await _upsertByKey(
          txn,
          'products',
          keyColumn: 'reference',
          keyValue: row['reference'] as String,
          values: row,
        );
      }

      // --- product_stocks ---
      for (final t in changes.tombstones.where((t) => t.table == 'product_stocks')) {
        final parts = t.mergeKey.split('|');
        if (parts.length != 2) continue;
        final productId = await _findIdByKey(txn, 'products', 'reference', parts[0]);
        final storeId = await _findIdByKey(txn, 'stores', 'name', parts[1]);
        if (productId == null || storeId == null) continue;
        applied += await txn.delete(
          'product_stocks',
          where: 'product_id = ? AND store_id = ? AND (updated_at IS NULL OR updated_at <= ?)',
          whereArgs: [productId, storeId, t.deletedAt],
        );
      }
      for (final row in changes.productStocks) {
        final productId = await _findIdByKey(txn, 'products', 'reference', row['product_reference'] as String);
        final storeId = await _findIdByKey(txn, 'stores', 'name', row['store_name'] as String);
        if (productId == null || storeId == null) continue;

        final incomingUpdatedAt = row['updated_at'] as String?;
        final existing = await txn.query(
          'product_stocks',
          where: 'product_id = ? AND store_id = ?',
          whereArgs: [productId, storeId],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('product_stocks', {
            'product_id': productId,
            'store_id': storeId,
            'initial_stock': row['initial_stock'],
            'updated_at': incomingUpdatedAt,
          });
          applied++;
        } else if (_isNewer(incomingUpdatedAt, existing.first['updated_at'] as String?)) {
          await txn.update(
            'product_stocks',
            {'initial_stock': row['initial_stock'], 'updated_at': incomingUpdatedAt},
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
          applied++;
        }
      }

      // --- stock_entries ---
      for (final t in changes.tombstones.where((t) => t.table == 'stock_entries')) {
        applied += await txn.delete(
          'stock_entries',
          where: 'sync_id = ? AND (updated_at IS NULL OR updated_at <= ?)',
          whereArgs: [t.mergeKey, t.deletedAt],
        );
      }
      for (final row in changes.stockEntries) {
        applied += await _upsertMovement(
          txn,
          'stock_entries',
          row,
          extraColumns: const ['supplier', 'reference', 'designation', 'quantity'],
        );
      }

      // --- stock_outputs ---
      for (final t in changes.tombstones.where((t) => t.table == 'stock_outputs')) {
        applied += await txn.delete(
          'stock_outputs',
          where: 'sync_id = ? AND (updated_at IS NULL OR updated_at <= ?)',
          whereArgs: [t.mergeKey, t.deletedAt],
        );
      }
      for (final row in changes.stockOutputs) {
        applied += await _upsertMovement(
          txn,
          'stock_outputs',
          row,
          extraColumns: const ['reference', 'designation', 'invoice_number', 'destination', 'quantity'],
        );
      }
    });
    return applied;
  }

  static bool _isNewer(String? incoming, String? local) {
    if (incoming == null) return false;
    if (local == null) return true;
    return incoming.compareTo(local) > 0;
  }

  static Future<int?> _findIdByKey(DatabaseExecutor txn, String table, String keyColumn, String keyValue) async {
    final rows = await txn.query(table, columns: ['id'], where: '$keyColumn = ?', whereArgs: [keyValue], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  /// Inserts a new row keyed by [keyColumn]/[keyValue] from [values], or
  /// updates the existing row if `values['updated_at']` is more recent.
  static Future<int> _upsertByKey(
    DatabaseExecutor txn,
    String table, {
    required String keyColumn,
    required String keyValue,
    required Map<String, Object?> values,
  }) async {
    final existing = await txn.query(table, where: '$keyColumn = ?', whereArgs: [keyValue], limit: 1);
    if (existing.isEmpty) {
      await txn.insert(table, values);
      return 1;
    }
    if (_isNewer(values['updated_at'] as String?, existing.first['updated_at'] as String?)) {
      await txn.update(table, values, where: 'id = ?', whereArgs: [existing.first['id']]);
      return 1;
    }
    return 0;
  }

  /// Inserts/updates a `stock_entries`/`stock_outputs` row keyed by
  /// `sync_id`, resolving the incoming `store_name` to a local `store_id`.
  static Future<int> _upsertMovement(
    DatabaseExecutor txn,
    String table,
    Map<String, Object?> row, {
    required List<String> extraColumns,
  }) async {
    final storeId = await _findIdByKey(txn, 'stores', 'name', row['store_name'] as String);
    if (storeId == null) return 0;

    final syncId = row['sync_id'] as String;
    final incomingUpdatedAt = row['updated_at'] as String?;
    final values = <String, Object?>{
      'date': row['date'],
      'store_id': storeId,
      'sync_id': syncId,
      'updated_at': incomingUpdatedAt,
      for (final c in extraColumns) c: row[c],
    };

    final existing = await txn.query(table, where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
    if (existing.isEmpty) {
      await txn.insert(table, values);
      return 1;
    }
    if (_isNewer(incomingUpdatedAt, existing.first['updated_at'] as String?)) {
      await txn.update(table, values, where: 'id = ?', whereArgs: [existing.first['id']]);
      return 1;
    }
    return 0;
  }
}
