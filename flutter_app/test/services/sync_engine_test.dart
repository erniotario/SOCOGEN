import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/db/schema.dart';
import 'package:socogen/data/db/sync_columns.dart';
import 'package:socogen/data/models/stock_entry.dart';
import 'package:socogen/data/models/stock_output.dart';
import 'package:socogen/data/repositories/product_repository.dart';
import 'package:socogen/data/repositories/stock_entry_repository.dart';
import 'package:socogen/data/repositories/stock_output_repository.dart';
import 'package:socogen/data/repositories/store_repository.dart';
import 'package:socogen/services/sync/sync_engine.dart';

/// Empty v2 database (no fixture rows), used to simulate a fresh device.
Future<Database> _openEmptyDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
      },
    ),
  );
}

/// Mirrors the SyncServer/SyncClient round trip: [a] pushes its changes to
/// [b], then [b] pushes its changes back to [a].
Future<void> _fullSync(Database a, Database b) async {
  final sinceA = await SyncEngine.getLastSyncAt(a);
  final aChanges = await SyncEngine.collectChanges(a, sinceA);
  await SyncEngine.applyChanges(b, aChanges);

  final sinceB = await SyncEngine.getLastSyncAt(b);
  final bChanges = await SyncEngine.collectChanges(b, sinceB);
  await SyncEngine.applyChanges(a, bChanges);

  final now = nowIso();
  await SyncEngine.setLastSyncAt(a, now);
  await SyncEngine.setLastSyncAt(b, now);
}

void main() {
  late Database dbA;
  late Database dbB;

  setUp(() async {
    dbA = await _openEmptyDb();
    dbB = await _openEmptyDb();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  test('new store, product and stock are pushed from A to B', () async {
    final storeId = await StoreRepository(database: dbA).createStore('Magasin Test');
    final productId = await ProductRepository(database: dbA).createProduct(
      reference: 'REFX',
      designation: 'Produit Test',
      unit: 'unité',
    );
    await ProductRepository(database: dbA).upsertProductStock(
      productId: productId,
      storeId: storeId,
      initialStock: 50,
    );

    await _fullSync(dbA, dbB);

    final stores = await dbB.query('stores', where: 'name = ?', whereArgs: ['Magasin Test']);
    expect(stores, hasLength(1));

    final products = await dbB.query('products', where: 'reference = ?', whereArgs: ['REFX']);
    expect(products, hasLength(1));
    expect(products.single['designation'], 'Produit Test');

    final stockRows = await dbB.rawQuery('''
      SELECT ps.initial_stock FROM product_stocks ps
      JOIN products p ON p.id = ps.product_id
      JOIN stores s ON s.id = ps.store_id
      WHERE p.reference = ? AND s.name = ?
    ''', ['REFX', 'Magasin Test']);
    expect(stockRows.single['initial_stock'], 50);
  });

  test('stock entry and output created on B are pushed to A', () async {
    await StoreRepository(database: dbA).createStore('Magasin Test');
    await _fullSync(dbA, dbB);

    final storeRowsB = await dbB.query('stores', where: 'name = ?', whereArgs: ['Magasin Test']);
    final storeIdB = storeRowsB.single['id'] as int;

    await StockEntryRepository(database: dbB).create(StockEntry(
      id: 0,
      date: '2026-06-15',
      supplier: 'Fournisseur Test',
      reference: 'REFX',
      designation: 'Produit Test',
      storeId: storeIdB,
      quantity: 7,
    ));
    await StockOutputRepository(database: dbB).create(StockOutput(
      id: 0,
      date: '2026-06-15',
      reference: 'REFX',
      designation: 'Produit Test',
      invoiceNumber: 'INV-T',
      storeId: storeIdB,
      destination: 'Client Test',
      quantity: 3,
    ));

    await _fullSync(dbA, dbB);

    final entriesA = await dbA.rawQuery('''
      SELECT se.quantity, s.name AS store_name FROM stock_entries se
      JOIN stores s ON s.id = se.store_id WHERE se.reference = ?
    ''', ['REFX']);
    expect(entriesA, hasLength(1));
    expect(entriesA.single['quantity'], 7);
    expect(entriesA.single['store_name'], 'Magasin Test');

    final outputsA = await dbA.rawQuery('''
      SELECT so.quantity, s.name AS store_name FROM stock_outputs so
      JOIN stores s ON s.id = so.store_id WHERE so.reference = ?
    ''', ['REFX']);
    expect(outputsA, hasLength(1));
    expect(outputsA.single['quantity'], 3);
  });

  test('conflicting product edit: most recent update wins on both sides', () async {
    final productRepoA = ProductRepository(database: dbA);
    final productRepoB = ProductRepository(database: dbB);

    await productRepoA.createProduct(reference: 'REFX', designation: 'Original', unit: 'unité');
    await _fullSync(dbA, dbB);

    final productA = (await productRepoA.getByReference('REFX'))!;
    await productRepoA.updateProduct(productA.copyWith(designation: 'Edition A'));

    await Future.delayed(const Duration(milliseconds: 5));

    final productB = (await productRepoB.getByReference('REFX'))!;
    await productRepoB.updateProduct(productB.copyWith(designation: 'Edition B'));

    await _fullSync(dbA, dbB);

    final finalA = (await productRepoA.getByReference('REFX'))!;
    final finalB = (await productRepoB.getByReference('REFX'))!;
    expect(finalA.designation, 'Edition B');
    expect(finalB.designation, 'Edition B');
  });

  test('product deleted on A is removed from B after sync', () async {
    final productRepoA = ProductRepository(database: dbA);

    await productRepoA.createProduct(reference: 'REFX', designation: 'À supprimer', unit: 'unité');
    await _fullSync(dbA, dbB);

    expect(await ProductRepository(database: dbB).referenceExists('REFX'), isTrue);

    final productA = (await productRepoA.getByReference('REFX'))!;
    await Future.delayed(const Duration(milliseconds: 5));
    await productRepoA.deleteProduct(productA.id);

    await _fullSync(dbA, dbB);

    expect(await ProductRepository(database: dbB).referenceExists('REFX'), isFalse);
  });
}
