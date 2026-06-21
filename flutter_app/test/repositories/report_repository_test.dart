import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/models/view_models.dart';
import 'package:socogen/data/repositories/report_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late ReportRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = ReportRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getReportRows returns one row per product x store with status', () async {
    final rows = await repo.getReportRows();
    expect(rows.length, 3);

    final ref1StoreA = rows.firstWhere((r) => r.reference == 'REF1' && r.storeName == 'StoreA');
    final ref1StoreB = rows.firstWhere((r) => r.reference == 'REF1' && r.storeName == 'StoreB');
    final ref2StoreA = rows.firstWhere((r) => r.reference == 'REF2' && r.storeName == 'StoreA');

    expect(ref1StoreA.current, 18);
    expect(ref1StoreA.status, StockStatus.enStock);
    expect(ref1StoreB.current, 10);
    expect(ref1StoreB.status, StockStatus.enStock);
    expect(ref2StoreA.current, 5);
    expect(ref2StoreA.status, StockStatus.stockFaible);
  });

  test('getReportRows filters by search, store and status', () async {
    final byStore = await repo.getReportRows(storeId: 2);
    expect(byStore.length, 1);
    expect(byStore.single.storeName, 'StoreB');

    final bySearch = await repo.getReportRows(search: 'REF2');
    expect(bySearch.length, 1);
    expect(bySearch.single.reference, 'REF2');

    final byStatus = await repo.getReportRows(status: StockStatus.stockFaible);
    expect(byStatus.length, 1);
    expect(byStatus.single.reference, 'REF2');
  });

  test('getStatusCounts aggregates over the full unfiltered dataset', () async {
    final counts = await repo.getStatusCounts();
    expect(counts.total, 3);
    expect(counts.enStock, 2);
    expect(counts.stockFaible, 1);
    expect(counts.rupture, 0);
  });
}
