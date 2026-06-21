import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/models/stock_entry.dart';
import 'package:socogen/data/repositories/stock_entry_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late StockEntryRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = StockEntryRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getAll returns entries newest first with store names', () async {
    final entries = await repo.getAll();
    expect(entries.length, 3);
    expect(entries.first.entry.date, '2026-02-01');
    expect(entries.first.storeName, 'StoreA');
    expect(entries.last.entry.date, '2026-01-05');
  });

  test('create, update and delete manage the stock_entries table', () async {
    final newId = await repo.create(const StockEntry(
      id: 0,
      date: '2026-03-01',
      supplier: 'Fournisseur D',
      reference: 'REF1',
      designation: 'Produit Un',
      storeId: 1,
      quantity: 4,
    ));

    var entries = await repo.getAll();
    expect(entries.first.entry.id, newId);
    expect(entries.first.entry.supplier, 'Fournisseur D');

    await repo.update(StockEntry(
      id: newId,
      date: '2026-03-01',
      supplier: 'Fournisseur D bis',
      reference: 'REF1',
      designation: 'Produit Un',
      storeId: 1,
      quantity: 6,
    ));
    entries = await repo.getAll();
    final updated = entries.firstWhere((e) => e.entry.id == newId);
    expect(updated.entry.supplier, 'Fournisseur D bis');
    expect(updated.entry.quantity, 6);

    await repo.delete(newId);
    entries = await repo.getAll();
    expect(entries.any((e) => e.entry.id == newId), isFalse);
  });
}
