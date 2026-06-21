import 'dart:io';

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
      },
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
        final now = nowIso();
        for (final name in AppSchema.defaultStores) {
          await db.insert('stores', {'name': name, 'updated_at': now});
        }
        await db.insert('company_settings', {'id': 1, 'name': 'SOCOGEN'});
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
      },
    );
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

    for (final table in ['stock_entries', 'stock_outputs']) {
      final rows = await db.query(table, columns: ['id'], where: 'sync_id IS NULL');
      for (final row in rows) {
        await db.update(
          table,
          {'sync_id': newSyncId(), 'updated_at': now},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
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
