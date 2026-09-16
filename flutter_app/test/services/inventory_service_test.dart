import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/stock/repositories/stock_repository.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/rapports/repositories/report_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_entry_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_output_repository.dart';
import 'package:socogen/modules/stock/services/inventory_service.dart';

import '../repositories/test_database.dart';

/// The fixture opens with REF1/StoreA at 18 and REF2/StoreA at 5.
void main() {
  late Database db;
  late InventoryService service;
  late StockRepository stock;

  setUp(() async {
    db = await openTestDatabase();
    stock = StockRepository(database: db);
    service = InventoryService(
      stockService: StockService(stockRepository: stock),
      entryRepository: StockEntryRepository(database: db),
      outputRepository: StockOutputRepository(database: db),
    );
  });

  tearDown(() async => db.close());

  Future<int> balance(String reference, int storeId) =>
      stock.balanceExcluding(reference: reference, storeId: storeId);

  InventoryCount count(String reference, int storeId, int counted, {int? theoretical}) =>
      InventoryCount(
        reference: reference,
        designation: 'Produit',
        storeId: storeId,
        storeName: 'StoreA',
        theoretical: theoretical ?? 0,
        counted: counted,
      );

  test('a shelf holding more than the ledger posts an entrée', () async {
    final report = await service.post([count('REF1', 1, 25)]);

    expect(report.surpluses, 1);
    expect(report.shortfalls, 0);
    expect(await balance('REF1', 1), 25);
  });

  test('a shelf holding less than the ledger posts a sortie', () async {
    final report = await service.post([count('REF1', 1, 12)]);

    expect(report.shortfalls, 1);
    expect(report.surpluses, 0);
    expect(await balance('REF1', 1), 12);
  });

  test('a count that matches writes nothing at all', () async {
    final before = await db.query('stock_entries');
    final report = await service.post([count('REF1', 1, 18)]);

    expect(report.adjustments, 0);
    expect(report.unchanged, 1);
    expect((await db.query('stock_entries')).length, before.length);
    expect(await balance('REF1', 1), 18);
  });

  test('the adjustment is a movement, never a rewritten opening stock', () async {
    final openingBefore = await db.query('product_stocks',
        columns: ['initial_stock'], where: 'product_id = 1 AND store_id = 1');

    await service.post([count('REF1', 1, 25)]);

    final openingAfter = await db.query('product_stocks',
        columns: ['initial_stock'], where: 'product_id = 1 AND store_id = 1');
    expect(openingAfter, openingBefore,
        reason: 'current stock is derived; the opening figure is not ours to touch');

    final adjustments = await db.query('stock_entries',
        where: 'supplier = ?', whereArgs: [InventoryService.label]);
    expect(adjustments.length, 1);
    expect(adjustments.single['quantity'], 7);
    expect(adjustments.single['reference'], 'REF1');
  });

  test('an adjustment is recognisable by its counterparty', () async {
    await service.post([count('REF1', 1, 25), count('REF2', 1, 2)]);

    final entry = (await db.query('stock_entries',
            where: 'supplier = ?', whereArgs: [InventoryService.label]))
        .single;
    expect(entry['reference'], 'REF1');

    final output = (await db.query('stock_outputs',
            where: 'destination = ?', whereArgs: [InventoryService.label]))
        .single;
    expect(output['reference'], 'REF2');
    expect(output['quantity'], 3, reason: '5 au registre, 2 comptés');
  });

  test('settles a negative balance, which is what it is for', () async {
    // Drive REF2/StoreA to -4, the state the Rapports banner flags.
    await db.insert('stock_outputs', {
      'date': '2026-03-02',
      'reference': 'REF2',
      'designation': 'Produit Deux',
      'invoice_number': 'INV4',
      'store_id': 1,
      'destination': 'Client Z',
      'quantity': 9,
    });
    expect(await balance('REF2', 1), -4);

    // The shelf actually holds 6.
    final report = await service.post([count('REF2', 1, 6)]);

    expect(report.surpluses, 1);
    expect(await balance('REF2', 1), 6);

    final negatives = await ReportRepository(database: db)
        .getReportRows(status: StockStatus.stockNegatif);
    expect(negatives, isEmpty, reason: 'the anomaly is settled, not hidden');
  });

  test('measures against the live balance, not the figure on screen', () async {
    // A draft counted when the ledger said 18; meanwhile a real sortie
    // of 3 lands, so the ledger now says 15. Posting must move the stock
    // to the counted 20, not blindly add the stale variance of 2.
    await db.insert('stock_outputs', {
      'date': '2026-03-03',
      'reference': 'REF1',
      'designation': 'Produit Un',
      'invoice_number': 'INV9',
      'store_id': 1,
      'destination': 'Client W',
      'quantity': 3,
    });

    await service.post([count('REF1', 1, 20, theoretical: 18)]);

    expect(await balance('REF1', 1), 20);
  });

  test('posting the same count twice is idempotent', () async {
    await service.post([count('REF1', 1, 25)]);
    final second = await service.post([count('REF1', 1, 25)]);

    expect(second.adjustments, 0);
    expect(second.unchanged, 1);
    expect(await balance('REF1', 1), 25);
  });

  test('a negative count is refused rather than guessed at', () async {
    final report = await service.post([count('REF1', 1, -5)]);

    expect(report.adjustments, 0);
    expect(report.problems, hasLength(1));
    expect(await balance('REF1', 1), 18, reason: 'rien ne doit bouger');
  });

  test('counts are scoped to their magasin', () async {
    await service.post([count('REF1', 2, 3)]);

    expect(await balance('REF1', 2), 3);
    expect(await balance('REF1', 1), 18, reason: 'StoreA est intact');
  });
}
