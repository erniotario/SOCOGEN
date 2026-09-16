import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/catalogue/repositories/product_repository.dart';
import 'package:socogen/modules/rapports/repositories/report_repository.dart';

import 'test_database.dart';

/// A stock below zero is not a low stock, it is an impossible one, and
/// it used to render exactly like the hundreds of articles legitimately
/// sitting at zero. These tests hold the two apart.
///
/// The shared fixture has no negative row on purpose -- every other test
/// documents its aggregates against it -- so each test here drives one
/// of its rows negative with an extra sortie of its own.
void main() {
  late Database db;
  late ReportRepository repo;

  /// Fixture rows after this runs:
  ///   REF1/StoreA = 18            -> en stock
  ///   REF1/StoreB = 10 - 10 =  0  -> rupture
  ///   REF2/StoreA =  5 -  9 = -4  -> stock negatif
  Future<void> seedOneZeroAndOneNegative() async {
    await db.insert('stock_outputs', {
      'date': '2026-03-01',
      'reference': 'REF1',
      'designation': 'Produit Un',
      'invoice_number': 'INV3',
      'store_id': 2,
      'destination': 'Client Z',
      'quantity': 10,
    });
    await db.insert('stock_outputs', {
      'date': '2026-03-02',
      'reference': 'REF2',
      'designation': 'Produit Deux',
      'invoice_number': 'INV4',
      'store_id': 1,
      'destination': 'Client Z',
      'quantity': 9,
    });
  }

  setUp(() async {
    db = await openTestDatabase();
    repo = ReportRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('fromCurrent tells an empty article apart from an impossible one', () {
    expect(StockStatus.fromCurrent(-1), StockStatus.stockNegatif);
    expect(StockStatus.fromCurrent(-38), StockStatus.stockNegatif);

    // The regression this whole feature exists for: zero is a normal,
    // legitimate state and must never be reported as an anomaly.
    expect(StockStatus.fromCurrent(0), StockStatus.rupture);

    expect(StockStatus.fromCurrent(1), StockStatus.stockFaible);
    expect(StockStatus.fromCurrent(9), StockStatus.stockFaible);
    expect(StockStatus.fromCurrent(10), StockStatus.enStock);
  });

  test('a negative balance carries its own label and colour, not the rupture one', () {
    expect(StockStatus.stockNegatif.label, 'Stock négatif');
    expect(StockStatus.stockNegatif.label, isNot(StockStatus.rupture.label));

    // Both are accented in the tables; only the badge separates them.
    expect(StockStatus.stockNegatif.isDepleted, isTrue);
    expect(StockStatus.rupture.isDepleted, isTrue);
    expect(StockStatus.enStock.isDepleted, isFalse);
    expect(StockStatus.stockFaible.isDepleted, isFalse);
  });

  test('getReportRows reports a below-zero row as stockNegatif', () async {
    await seedOneZeroAndOneNegative();
    final rows = await repo.getReportRows();

    final negative = rows.firstWhere((r) => r.reference == 'REF2');
    expect(negative.current, -4);
    expect(negative.status, StockStatus.stockNegatif);

    final empty = rows.firstWhere(
      (r) => r.reference == 'REF1' && r.storeName == 'StoreB',
    );
    expect(empty.current, 0);
    expect(empty.status, StockStatus.rupture);
  });

  test('the status filter narrows the table to the rows to settle', () async {
    await seedOneZeroAndOneNegative();

    final negatives = await repo.getReportRows(status: StockStatus.stockNegatif);
    expect(negatives.length, 1);
    expect(negatives.single.reference, 'REF2');

    // Asking for ruptures must not sweep the negative row back in.
    final ruptures = await repo.getReportRows(status: StockStatus.rupture);
    expect(ruptures.length, 1);
    expect(ruptures.single.storeName, 'StoreB');
  });

  test('getStatusCounts counts negatives apart from ruptures', () async {
    await seedOneZeroAndOneNegative();
    final counts = await repo.getStatusCounts();

    expect(counts.total, 3);
    expect(counts.enStock, 1);
    expect(counts.stockFaible, 0);
    expect(counts.rupture, 1);
    expect(counts.negatif, 1);

    // The SQL thresholds and StockStatus.fromCurrent are written twice
    // and must agree; this is what catches them drifting apart.
    final rows = await repo.getReportRows();
    int tally(StockStatus s) => rows.where((r) => r.status == s).length;
    expect(tally(StockStatus.enStock), counts.enStock);
    expect(tally(StockStatus.stockFaible), counts.stockFaible);
    expect(tally(StockStatus.rupture), counts.rupture);
    expect(tally(StockStatus.stockNegatif), counts.negatif);
  });

  test('a clean ledger reports no anomaly at all', () async {
    final counts = await repo.getStatusCounts();
    expect(counts.negatif, 0);
    expect(counts.rupture, 0);
  });

  group('balanceExcluding', () {
    late ProductRepository products;

    setUp(() => products = ProductRepository(database: db));

    test('with nothing excluded it matches the plain balance', () async {
      // REF1/StoreA = 10 initial + 20 entered - 12 taken out.
      expect(
        await products.balanceExcluding(reference: 'REF1', storeId: 1),
        18,
      );
      // REF1/StoreB = 5 + 5, untouched by StoreA's movements.
      expect(
        await products.balanceExcluding(reference: 'REF1', storeId: 2),
        10,
      );
    });

    test('leaves out the one movement it is told to', () async {
      // Without the +20 entrée (id 1) the store is 10 - 12 = -2.
      expect(
        await products.balanceExcluding(
          reference: 'REF1',
          storeId: 1,
          excludeEntryId: 1,
        ),
        -2,
      );
      // Without the -12 sortie (id 1) it is 10 + 20 = 30.
      expect(
        await products.balanceExcluding(
          reference: 'REF1',
          storeId: 1,
          excludeOutputId: 1,
        ),
        30,
      );
    });

    test('excluding a movement of another store changes nothing', () async {
      // Entry id 2 belongs to StoreB, so asking about StoreA is a no-op.
      expect(
        await products.balanceExcluding(
          reference: 'REF1',
          storeId: 1,
          excludeEntryId: 2,
        ),
        18,
      );
    });

    test('an unknown reference or store is simply empty, not an error', () async {
      expect(
        await products.balanceExcluding(reference: 'NOPE', storeId: 1),
        0,
      );
      expect(
        await products.balanceExcluding(reference: 'REF1', storeId: 99),
        0,
      );
    });

    test('answers what an edit would leave behind', () async {
      // Raising sortie id 1 on REF1/StoreA from 12 to 40: the ledger
      // still holds the old 12, so only excluding it shows the truth.
      final base = await products.balanceExcluding(
        reference: 'REF1',
        storeId: 1,
        excludeOutputId: 1,
      );
      expect(base - 40, -10);
      expect(StockStatus.fromCurrent(base - 40), StockStatus.stockNegatif);
    });
  });
}
