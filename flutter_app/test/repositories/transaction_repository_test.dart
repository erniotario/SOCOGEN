import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/stock/repositories/transaction_repository.dart';

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

  test('getTransactions over all products carries a balance per product', () async {
    final rows = await repo.getTransactions();

    expect(rows.map((r) => r.date).toList(),
        ['2026-01-05', '2026-01-08', '2026-01-10', '2026-02-01', '2026-02-05']);
    // REF1 opens at 15 and runs 35 -> 23 -> 28; REF2 opens at 0 and runs
    // 8 -> 5. Each row shows that product's stock, not a total across
    // unrelated articles.
    expect(rows.map((r) => r.balance).toList(), [35, 23, 28, 8, 5]);
  });

  test('a date filter hides rows without falsifying the balance', () async {
    final rows = await repo.getTransactions(dateFrom: '2026-01-08');

    expect(rows.map((r) => r.date).toList(),
        ['2026-01-08', '2026-01-10', '2026-02-01', '2026-02-05']);
    // 2026-01-05's +20 is not shown but still counted: REF1 stands at 23
    // after the 12 leaving on the 8th, not at -12 + 15.
    expect(rows.map((r) => r.balance).toList(), [23, 28, 8, 5]);
  });

  test('a type filter hides rows without falsifying the balance', () async {
    final rows = await repo.getTransactions(type: TransactionType.output);

    expect(rows.map((r) => r.reference).toList(), ['REF1', 'REF2']);
    expect(rows.map((r) => r.balance).toList(), [23, 5]);
  });

  test('a store filter scopes the balance to that store', () async {
    final rows = await repo.getTransactions(reference: 'REF1', storeId: 1);

    // StoreA holds 10 of REF1 to start, then +20 and -12.
    expect(rows.map((r) => r.balance).toList(), [30, 18]);
  });

  test('the last row of each product matches its current stock', () async {
    final rows = await repo.getTransactions();

    final lastByRef = <String, int>{};
    for (final row in rows) {
      lastByRef[row.reference] = row.balance;
    }
    expect(lastByRef['REF1'], 28);
    expect(lastByRef['REF2'], 5);
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
