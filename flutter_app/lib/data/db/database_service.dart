import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_factory_init.dart';
import 'schema.dart';
import 'sync_columns.dart';

/// Owns the single SQLite database connection used by the whole app.
///
/// On first launch, the bundled, pre-populated `socogen_seed.db` asset is
/// copied to a writable per-device location and opened from there. On
/// subsequent launches the existing (possibly modified) file is opened
/// as-is, so each device keeps its own local data with no sync.
class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  static const String _seedAssetPath = 'assets/db/socogen_seed.db';
  static const String _dbFileName = 'socogen_stock.db';

  Database? _database;

  /// Test seam: supply a ready-made database so widget tests can drive
  /// the real screens. Without it, [database] resolves a path with
  /// path_provider and copies the seed asset, neither of which works in
  /// a plain widget test.
  @visibleForTesting
  set databaseForTesting(Database? db) => _database = db;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final db = await _initDatabase();
    _database = db;
    return db;
  }

  Future<Database> _initDatabase() async {
    initializeDatabaseFactory();

    final dbPath = await _resolveDatabasePath();
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      await _copySeedDatabase(dbFile);
    }

    return openDatabase(
      dbPath,
      version: AppSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await _applyPerformancePragmas(db);
      },
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
        for (final statement in AppSchema.createIndexStatements) {
          await db.execute(statement);
        }
        final now = nowIso();
        for (final name in AppSchema.defaultStores) {
          await db.insert('stores', {'name': name, 'updated_at': now});
        }
        // Blank, not 'SOCOGEN'. The first-run setup asks whose business
        // this is; a name filled in here would put the first customer's
        // identity on every other customer's reports.
        await db.insert('company_settings', {'id': 1, 'name': ''});
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
      },
    );
  }

  /// Tunes SQLite for the writes this app actually does. NORMAL drops
  /// the fsync per statement that makes an import or a sync crawl on
  /// phone storage; WAL lets a read run while a write is in flight. Both
  /// are safe for a single-process app: a crash can cost the last
  /// transaction, never the file.
  ///
  /// Read, never executed. Setting `journal_mode` answers with the mode
  /// SQLite settled on, and Android's SQLiteDatabase refuses any
  /// statement that returns rows through `execute()` -- "queries can be
  /// performed using SQLiteDatabase query or rawQuery methods only". As
  /// `execute` it threw while opening the database, which left the app
  /// unable to reach its own data at all.
  ///
  /// Each pragma is allowed to fail on its own, because none of them is
  /// worth failing startup over: a platform that refuses one keeps its
  /// default, which is slower to write and just as correct. On Android
  /// WAL is meant to be switched on by the
  /// `com.tekartik.sqflite.wal_enabled` manifest flag, which hands
  /// SQLiteDatabase the flag at open time instead of arguing with it
  /// afterwards, so expect it to stay off here.
  Future<void> _applyPerformancePragmas(Database db) async {
    for (final pragma in const [
      'PRAGMA journal_mode = WAL',
      'PRAGMA synchronous = NORMAL',
    ]) {
      try {
        await db.rawQuery(pragma);
      } catch (_) {
        // Keep the platform default for this one.
      }
    }
  }

  /// Creates the query indexes. The seeded asset database ships without
  /// them and every database created before v3 lacks them, so this runs
  /// as an upgrade step rather than only at creation.
  Future<void> _migrateToV3(Database db) async {
    for (final statement in AppSchema.createIndexStatements) {
      await db.execute(statement);
    }
  }

  /// Adds the `updated_at`/`sync_id` columns and the `sync_tombstones`/
  /// `sync_meta` tables used by the local Wi-Fi synchronisation feature,
  /// then backfills existing rows so they are treated as "changed now"
  /// the first time a sync runs.
  Future<void> _migrateToV2(Database db) async {
    for (final statement in AppSchema.migrationV1ToV2) {
      await db.execute(statement);
    }

    final now = nowIso();
    await db.update('stores', {'updated_at': now}, where: 'updated_at IS NULL');
    await db.update('products', {'updated_at': now}, where: 'updated_at IS NULL');
    await db.update('product_stocks', {'updated_at': now}, where: 'updated_at IS NULL');

    // One statement per movement, but committed as a single batch: a
    // few thousand rows each in their own transaction is minutes of
    // fsync on a phone, and this runs on the first launch after an
    // update.
    for (final table in ['stock_entries', 'stock_outputs']) {
      final rows = await db.query(table, columns: ['id'], where: 'sync_id IS NULL');
      final batch = db.batch();
      for (final row in rows) {
        batch.update(
          table,
          {'sync_id': newSyncId(), 'updated_at': now},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await batch.commit(noResult: true);
    }
  }

  Future<String> _resolveDatabasePath() async {
    final Directory dir;
    if (Platform.isWindows) {
      dir = Directory(p.dirname(Platform.resolvedExecutable));
    } else if (Platform.isLinux || Platform.isMacOS) {
      dir = await getApplicationSupportDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, _dbFileName);
  }

  Future<void> _copySeedDatabase(File dbFile) async {
    try {
      final data = await rootBundle.load(_seedAssetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await dbFile.parent.create(recursive: true);
      await dbFile.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Seed asset missing: leave dbFile absent so openDatabase()
      // creates an empty database and runs onCreate as a fallback.
    }
  }

  /// Closes the underlying connection. Mainly useful for tests.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Closes the current connection and replaces the local database file
  /// with the one at [sourcePath]. The app must be restarted afterwards
  /// for the imported data to be loaded.
  Future<void> replaceDatabaseFile(String sourcePath) async {
    await close();
    final dbPath = await _resolveDatabasePath();
    await File(sourcePath).copy(dbPath);
  }

  /// Closes the current connection and replaces the local database file
  /// with an empty one, so the next launch recreates a blank schema
  /// (factory reset). The app must be restarted afterwards.
  Future<void> resetDatabaseFile() async {
    await close();
    final dbPath = await _resolveDatabasePath();
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
    await file.create(recursive: true);
  }
}
