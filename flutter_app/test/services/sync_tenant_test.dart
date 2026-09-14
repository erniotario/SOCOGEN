import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/db/schema.dart';
import 'package:socogen/data/db/sync_columns.dart';
import 'package:socogen/services/sync/sync_engine.dart';
import 'package:socogen/services/sync/sync_models.dart';

/// A device belongs to one business, and the sync merge runs on natural
/// keys -- a store by its name, a product by its reference. Two businesses
/// both keeping a "Dépôt" and a "RIZ25" is not unusual; letting their
/// devices exchange rows would fuse the two catalogues without an error,
/// and the more recent updated_at would overwrite real stock with a
/// stranger's.
///
/// These tests cover the identity that prevents it, and the first-contact
/// rule that lets two devices of the *same* business still pair.
Future<Database> _openEmptyDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      // Without singleInstance:false, opening inMemoryDatabasePath twice
      // hands back the SAME database, and a two-device test quietly
      // becomes one device syncing with itself -- every assertion about
      // the peer passes because the row never went anywhere.
      singleInstance: false,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
      },
    ),
  );
}

/// Gives [db] a magasin and an article, both named the way two unrelated
/// wholesalers plausibly would.
Future<void> _seedCollidingCatalogue(Database db, {required int quantity}) async {
  final now = nowIso();
  await db.insert('stores', {'id': 1, 'name': 'Dépôt', 'updated_at': now});
  await db.insert('products', {
    'id': 1,
    'reference': 'RIZ25',
    'designation': 'RIZ 25KG',
    'unit': 'sac',
    'updated_at': now,
  });
  await db.insert('product_stocks', {
    'product_id': 1,
    'store_id': 1,
    'initial_stock': quantity,
    'updated_at': now,
  });
}

Future<int> _openingStock(Database db) async {
  final rows = await db.query('product_stocks', columns: ['initial_stock']);
  return (rows.first['initial_stock'] as num).toInt();
}

void main() {
  late Database dbA;
  late Database dbB;

  setUp(() async {
    dbA = await _openEmptyDb();
    dbB = await _openEmptyDb();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  group('identity', () {
    test('a fresh database is unclaimed', () async {
      expect(await SyncEngine.getTenantId(dbA), isNull);
    });

    test('claiming is one-way: a claim is never reassigned', () async {
      await SyncEngine.claimTenant(dbA, 'business-one');
      await SyncEngine.claimTenant(dbA, 'business-two');

      expect(
        await SyncEngine.getTenantId(dbA),
        'business-one',
        reason: 'an identity that can be reassigned defeats the check',
      );
    });
  });

  group('first contact', () {
    test('two unclaimed devices settle on one shared identity', () async {
      final settled = await SyncEngine.reconcileTenant(dbA, null);
      await SyncEngine.reconcileTenant(dbB, settled);

      expect(settled, isNotEmpty);
      expect(await SyncEngine.getTenantId(dbA), settled);
      expect(await SyncEngine.getTenantId(dbB), settled);
    });

    test('an unclaimed device adopts the peer it first syncs with', () async {
      await SyncEngine.claimTenant(dbA, 'business-one');

      final settled = await SyncEngine.reconcileTenant(dbB, 'business-one');

      expect(settled, 'business-one');
      expect(await SyncEngine.getTenantId(dbB), 'business-one');
    });

    test('a claimed device is unchanged by meeting an unclaimed one', () async {
      await SyncEngine.claimTenant(dbA, 'business-one');

      expect(await SyncEngine.reconcileTenant(dbA, null), 'business-one');
      expect(await SyncEngine.getTenantId(dbA), 'business-one');
    });

    test('two devices of the same business keep syncing', () async {
      await SyncEngine.claimTenant(dbA, 'business-one');
      await SyncEngine.claimTenant(dbB, 'business-one');

      await expectLater(
        SyncEngine.reconcileTenant(dbA, 'business-one'),
        completion('business-one'),
      );
    });
  });

  group('refusal', () {
    test('two businesses are refused, in French, before anything merges', () async {
      await SyncEngine.claimTenant(dbA, 'business-one');
      await SyncEngine.claimTenant(dbB, 'business-two');

      await expectLater(
        SyncEngine.reconcileTenant(dbA, 'business-two'),
        throwsA(isA<TenantMismatch>()),
      );

      const mismatch = TenantMismatch();
      expect(mismatch.message, contains('autre entreprise'));
      expect(
        mismatch.message,
        contains('aucune donnée'),
        reason: 'the operator needs to know nothing was exchanged',
      );
    });

    test('a refused sync leaves both catalogues exactly as they were', () async {
      await _seedCollidingCatalogue(dbA, quantity: 40);
      await _seedCollidingCatalogue(dbB, quantity: 900);
      await SyncEngine.claimTenant(dbA, 'business-one');
      await SyncEngine.claimTenant(dbB, 'business-two');

      // Mirrors SyncServer: reconcile first, apply only if it returns.
      final changes = await SyncEngine.collectChanges(dbB, syncEpoch);
      try {
        await SyncEngine.reconcileTenant(dbA, 'business-two');
        await SyncEngine.applyChanges(dbA, changes);
        fail('the exchange should have been refused');
      } on TenantMismatch {
        // expected
      }

      expect(await _openingStock(dbA), 40, reason: 'untouched');
      expect(await _openingStock(dbB), 900, reason: 'untouched');
      expect(await SyncEngine.getTenantId(dbA), 'business-one');
    });

    test('the guard is load-bearing: the same rows DO fuse without it', () async {
      // Same two catalogues, same colliding names -- but claimed by one
      // business, so the exchange is legitimate and goes through. If this
      // ever stops merging, the refusal test above has become vacuous and
      // would pass for the wrong reason.
      await _seedCollidingCatalogue(dbA, quantity: 40);
      await _seedCollidingCatalogue(dbB, quantity: 900);
      await SyncEngine.claimTenant(dbA, 'business-one');
      await SyncEngine.claimTenant(dbB, 'business-one');

      final changes = await SyncEngine.collectChanges(dbB, syncEpoch);
      await SyncEngine.reconcileTenant(dbA, 'business-one');
      await SyncEngine.applyChanges(dbA, changes);

      expect(
        await _openingStock(dbA),
        900,
        reason: 'B is the more recent write, so it wins on a shared reference',
      );
    });
  });

  group('the wire', () {
    test('a change set carries the identity of the device sending it', () {
      const empty = ChangeSet();
      expect(empty.tenantId, isNull);

      final stamped = empty.withTenant('business-one');
      expect(stamped.tenantId, 'business-one');
      expect(
        ChangeSet.fromJson(stamped.toJson()).tenantId,
        'business-one',
        reason: 'identity has to survive the round trip through JSON',
      );
    });

    test('identity is not a record and must not make a sync look non-empty', () {
      final stamped = const ChangeSet().withTenant('business-one');

      expect(stamped.isEmpty, isTrue);
      expect(stamped.recordCount, 0);
    });

    test('a peer running an older build sends no identity at all', () {
      final legacy = ChangeSet.fromJson({
        'stores': <Object?>[],
        'products': <Object?>[],
        'productStocks': <Object?>[],
        'stockEntries': <Object?>[],
        'stockOutputs': <Object?>[],
        'tombstones': <Object?>[],
      });

      expect(legacy.tenantId, isNull, reason: 'absent, not an error');
    });
  });
}
