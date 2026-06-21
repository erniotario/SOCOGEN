import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/repositories/store_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late StoreRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = StoreRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getAllStores returns stores ordered by name', () async {
    final stores = await repo.getAllStores();
    expect(stores.map((s) => s.name).toList(), ['StoreA', 'StoreB']);
  });

  test('getStoreOverview computes product count and total stock per store', () async {
    final overview = await repo.getStoreOverview();
    final storeA = overview.firstWhere((o) => o.store.name == 'StoreA');
    final storeB = overview.firstWhere((o) => o.store.name == 'StoreB');

    expect(storeA.productCount, 2);
    expect(storeA.totalStock, 23);
    expect(storeB.productCount, 1);
    expect(storeB.totalStock, 10);
  });

  test('getStoreDetails computes entries/outputs/current stock for a store', () async {
    final details = await repo.getStoreDetails(1);

    expect(details.store.name, 'StoreA');
    expect(details.productCount, 2);
    expect(details.totalEntries, 28);
    expect(details.totalOutputs, 15);
    expect(details.currentStock, 23);
  });

  test('nameExists detects duplicates and respects excludeId', () async {
    expect(await repo.nameExists('StoreA'), isTrue);
    expect(await repo.nameExists('StoreC'), isFalse);
    expect(await repo.nameExists('StoreA', excludeId: 1), isFalse);
  });

  test('createStore, updateStore and deleteStore manage the stores table', () async {
    final newId = await repo.createStore('StoreC');
    expect(await repo.nameExists('StoreC'), isTrue);

    await repo.updateStore(newId, 'StoreC Renamed');
    final stores = await repo.getAllStores();
    expect(stores.any((s) => s.name == 'StoreC Renamed'), isTrue);

    expect(await repo.hasLinkedData(newId), isFalse);
    expect(await repo.hasLinkedData(1), isTrue);

    await repo.deleteStore(newId);
    final after = await repo.getAllStores();
    expect(after.any((s) => s.name == 'StoreC Renamed'), isFalse);
  });
}
