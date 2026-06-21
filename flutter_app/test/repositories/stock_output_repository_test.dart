import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/models/stock_output.dart';
import 'package:socogen/data/repositories/stock_output_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late StockOutputRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = StockOutputRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getAll returns outputs newest first with store names', () async {
    final outputs = await repo.getAll();
    expect(outputs.length, 2);
    expect(outputs.first.output.date, '2026-02-05');
    expect(outputs.first.storeName, 'StoreA');
    expect(outputs.last.output.date, '2026-01-08');
  });

  test('create, update and delete manage the stock_outputs table', () async {
    final newId = await repo.create(const StockOutput(
      id: 0,
      date: '2026-03-02',
      reference: 'REF1',
      designation: 'Produit Un',
      invoiceNumber: 'INV3',
      storeId: 2,
      destination: 'Client Z',
      quantity: 2,
    ));

    var outputs = await repo.getAll();
    expect(outputs.first.output.id, newId);
    expect(outputs.first.output.destination, 'Client Z');

    await repo.update(StockOutput(
      id: newId,
      date: '2026-03-02',
      reference: 'REF1',
      designation: 'Produit Un',
      invoiceNumber: 'INV3 bis',
      storeId: 2,
      destination: 'Client Z bis',
      quantity: 3,
    ));
    outputs = await repo.getAll();
    final updated = outputs.firstWhere((o) => o.output.id == newId);
    expect(updated.output.invoiceNumber, 'INV3 bis');
    expect(updated.output.quantity, 3);

    await repo.delete(newId);
    outputs = await repo.getAll();
    expect(outputs.any((o) => o.output.id == newId), isFalse);
  });
}
