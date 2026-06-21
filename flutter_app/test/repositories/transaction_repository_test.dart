import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/models/view_models.dart';
import 'package:socogen/data/repositories/transaction_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late TransactionRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = TransactionRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getTransactions for REF1 computes running balance starting from initial stock', () async {
    final rows = await repo.getTransactions(reference: 'REF1');

    // Oldest first; chronological balances were 35 -> 23 -> 28.
    expect(rows.map((r) => r.date).toList(), ['2026-01-05', '2026-01-08', '2026-01-10']);
    expect(rows.map((r) => r.balance).toList(), [35, 23, 28]);

    // Last (newest) entry's balance reflects the chronological end state,
    // i.e. the product's current stock.
    expect(rows.last.balance, 28);
    expect(rows.first.balance, 35);
  });

  test('getTransactions for all products starts balance at 0', () async {
    final rows = await repo.getTransactions();

    expect(rows.map((r) => r.date).toList(),
        ['2026-01-05', '2026-01-08', '2026-01-10', '2026-02-01', '2026-02-05']);
    expect(rows.map((r) => r.balance).toList(), [20, 8, 13, 21, 18]);
  });

  test('getTransactions filters by type', () async {
    final entriesOnly = await repo.getTransactions(type: TransactionType.entry);
    expect(entriesOnly.every((r) => r.type == TransactionType.entry), isTrue);
    expect(entriesOnly.length, 3);

    final outputsOnly = await repo.getTransactions(type: TransactionType.output);
    expect(outputsOnly.every((r) => r.type == TransactionType.output), isTrue);
    expect(outputsOnly.length, 2);
  });

  test('getTransactions filters by store and date range', () async {
    final storeB = await repo.getTransactions(storeId: 2);
    expect(storeB.length, 1);
    expect(storeB.single.storeName, 'StoreB');

    final ranged = await repo.getTransactions(dateFrom: '2026-02-01', dateTo: '2026-02-28');
    expect(ranged.length, 2);
    expect(ranged.every((r) => r.date.startsWith('2026-02')), isTrue);
  });
}
