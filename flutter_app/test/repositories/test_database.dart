import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/db/schema.dart';

/// Builds an in-memory SQLite database pre-populated with a small,
/// hand-computed fixture dataset shared by the repository unit tests.
///
/// Fixture data:
/// - Stores: id=1 "StoreA", id=2 "StoreB"
/// - Products: id=1 "REF1" (Produit Un), id=2 "REF2" (Produit Deux)
/// - product_stocks: (REF1,StoreA)=10, (REF1,StoreB)=5, (REF2,StoreA)=0
/// - stock_entries:
///     2026-01-05 REF1 StoreA +20 (Fournisseur A)
///     2026-01-10 REF1 StoreB +5  (Fournisseur B)
///     2026-02-01 REF2 StoreA +8  (Fournisseur C)
/// - stock_outputs:
///     2026-01-08 REF1 StoreA -12 (INV1, Client X)
///     2026-02-05 REF2 StoreA -3  (INV2, Client Y)
///
/// Expected aggregates:
/// - REF1 current = 15 (initial) + 25 (entries) - 12 (outputs) = 28 -> En stock
/// - REF2 current = 0  (initial) + 8  (entries) - 3  (outputs) = 5  -> Stock faible
/// - StoreAvailability(REF1): StoreA=18, StoreB=10
/// - Status counts: total=3, enStock=2, stockFaible=1, rupture=0
/// - StoreOverview: StoreA productCount=2/totalStock=23, StoreB productCount=1/totalStock=10
/// - StoreDetails(StoreA): productCount=2/totalEntries=28/totalOutputs=15/currentStock=23
/// - Transactions(REF1): initialSum=15, chronological balances 35 -> 23 -> 28
/// - Transactions(all): initialSum=0, chronological balances 20 -> 8 -> 13 -> 21 -> 18
Future<Database> openTestDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
      },
    ),
  );

  await db.insert('stores', {'id': 1, 'name': 'StoreA'});
  await db.insert('stores', {'id': 2, 'name': 'StoreB'});

  await db.insert('products', {
    'id': 1,
    'reference': 'REF1',
    'designation': 'Produit Un',
    'unit': 'unité',
  });
  await db.insert('products', {
    'id': 2,
    'reference': 'REF2',
    'designation': 'Produit Deux',
    'unit': 'unité',
  });

  await db.insert('product_stocks', {'id': 1, 'product_id': 1, 'store_id': 1, 'initial_stock': 10});
  await db.insert('product_stocks', {'id': 2, 'product_id': 1, 'store_id': 2, 'initial_stock': 5});
  await db.insert('product_stocks', {'id': 3, 'product_id': 2, 'store_id': 1, 'initial_stock': 0});

  await db.insert('stock_entries', {
    'id': 1,
    'date': '2026-01-05',
    'supplier': 'Fournisseur A',
    'reference': 'REF1',
    'designation': 'Produit Un',
    'store_id': 1,
    'quantity': 20,
  });
  await db.insert('stock_entries', {
    'id': 2,
    'date': '2026-01-10',
    'supplier': 'Fournisseur B',
    'reference': 'REF1',
    'designation': 'Produit Un',
    'store_id': 2,
    'quantity': 5,
  });
  await db.insert('stock_entries', {
    'id': 3,
    'date': '2026-02-01',
    'supplier': 'Fournisseur C',
    'reference': 'REF2',
    'designation': 'Produit Deux',
    'store_id': 1,
    'quantity': 8,
  });

  await db.insert('stock_outputs', {
    'id': 1,
    'date': '2026-01-08',
    'reference': 'REF1',
    'designation': 'Produit Un',
    'invoice_number': 'INV1',
    'store_id': 1,
    'destination': 'Client X',
    'quantity': 12,
  });
  await db.insert('stock_outputs', {
    'id': 2,
    'date': '2026-02-05',
    'reference': 'REF2',
    'designation': 'Produit Deux',
    'invoice_number': 'INV2',
    'store_id': 1,
    'destination': 'Client Y',
    'quantity': 3,
  });

  return db;
}
