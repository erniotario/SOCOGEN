import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/models/view_models.dart';
import 'package:socogen/data/repositories/product_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late ProductRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = ProductRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getProductOverviews computes current stock and status per product', () async {
    final overviews = await repo.getProductOverviews();
    final ref1 = overviews.firstWhere((o) => o.product.reference == 'REF1');
    final ref2 = overviews.firstWhere((o) => o.product.reference == 'REF2');

    expect(ref1.currentStock, 28);
    expect(ref1.status, StockStatus.enStock);
    expect(ref2.currentStock, 5);
    expect(ref2.status, StockStatus.stockFaible);
  });

  test('getProductOverviews exposes store names, count and first-stock fields', () async {
    final overviews = await repo.getProductOverviews();
    final ref1 = overviews.firstWhere((o) => o.product.reference == 'REF1');
    final ref2 = overviews.firstWhere((o) => o.product.reference == 'REF2');

    expect(ref1.storeNames, 'StoreA / StoreB');
    expect(ref1.stockCount, 2);
    expect(ref1.firstStockId, 1);
    expect(ref1.firstStoreId, 1);
    expect(ref1.firstStoreInitialStock, 10);

    expect(ref2.storeNames, 'StoreA');
    expect(ref2.stockCount, 1);
    expect(ref2.firstStockId, 3);
    expect(ref2.firstStoreId, 1);
    expect(ref2.firstStoreInitialStock, 0);
  });

  test('hasMovements is true for referenced products and false otherwise', () async {
    expect(await repo.hasMovements('REF1'), isTrue);
    expect(await repo.hasMovements('REF2'), isTrue);
    expect(await repo.hasMovements('NOPE'), isFalse);
  });

  test('getProductOverviews filters by search term', () async {
    final overviews = await repo.getProductOverviews(search: 'REF2');
    expect(overviews.length, 1);
    expect(overviews.single.product.reference, 'REF2');
  });

  test('getByReference and referenceExists', () async {
    final product = await repo.getByReference('REF1');
    expect(product, isNotNull);
    expect(product!.designation, 'Produit Un');

    expect(await repo.referenceExists('REF1'), isTrue);
    expect(await repo.referenceExists('REF1', excludeId: product.id), isFalse);
    expect(await repo.referenceExists('REF9'), isFalse);
  });

  test('getProductStocks returns per-store rows with store names', () async {
    final stocks = await repo.getProductStocks(1);
    expect(stocks.length, 2);
    expect(stocks.map((s) => s.storeName).toSet(), {'StoreA', 'StoreB'});
    expect(stocks.firstWhere((s) => s.storeName == 'StoreA').stock.initialStock, 10);
    expect(stocks.firstWhere((s) => s.storeName == 'StoreB').stock.initialStock, 5);
  });

  test('getStoreAvailability computes available stock per store for REF1', () async {
    final availability = await repo.getStoreAvailability('REF1', 1);
    final storeA = availability.firstWhere((a) => a.storeName == 'StoreA');
    final storeB = availability.firstWhere((a) => a.storeName == 'StoreB');

    expect(storeA.available, 18);
    expect(storeB.available, 10);
  });

  test('createProduct, updateProduct and deleteProduct manage the products table', () async {
    final newId = await repo.createProduct(
      reference: 'REF3',
      designation: 'Produit Trois',
      unit: 'kg',
    );
    expect(await repo.referenceExists('REF3'), isTrue);

    final created = (await repo.getByReference('REF3'))!;
    await repo.updateProduct(created.copyWith(designation: 'Produit Trois Bis'));
    final updated = await repo.getByReference('REF3');
    expect(updated!.designation, 'Produit Trois Bis');

    await repo.deleteProduct(newId);
    expect(await repo.getByReference('REF3'), isNull);
  });

  test('updateProductStock changes store and initial stock for a given row', () async {
    await repo.updateProductStock(2, storeId: 2, initialStock: 99);
    final stocks = await repo.getProductStocks(1);
    final updated = stocks.firstWhere((s) => s.stock.id == 2);
    expect(updated.stock.storeId, 2);
    expect(updated.stock.initialStock, 99);
    expect(updated.storeName, 'StoreB');
  });

  test('upsertProductStock inserts then updates the product_stocks row', () async {
    await repo.upsertProductStock(productId: 2, storeId: 2, initialStock: 7);
    var stocks = await repo.getProductStocks(2);
    expect(stocks.firstWhere((s) => s.storeName == 'StoreB').stock.initialStock, 7);

    await repo.upsertProductStock(productId: 2, storeId: 2, initialStock: 9);
    stocks = await repo.getProductStocks(2);
    final storeBStocks = stocks.where((s) => s.storeName == 'StoreB').toList();
    expect(storeBStocks.length, 1);
    expect(storeBStocks.single.stock.initialStock, 9);
  });
}
