import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/shared/models/company_settings.dart';

class SettingsRepository {
  SettingsRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  Future<CompanySettings> getSettings() async {
    final db = await _db;
    final rows = await db.query('company_settings', where: 'id = ?', whereArgs: [1], limit: 1);
    if (rows.isEmpty) return const CompanySettings();
    return CompanySettings.fromMap(rows.first);
  }

  Future<void> saveSettings(CompanySettings settings) async {
    final db = await _db;
    await db.insert(
      'company_settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Key in `sync_meta` recording that someone has said whose business
  /// this database belongs to.
  ///
  /// `sync_meta` is the app's key/value store rather than sync's private
  /// table -- `tenant_id` lives there too -- and it is deliberately not
  /// part of a `ChangeSet`, so this stays a fact about *this device*.
  static const String _configuredKey = 'company_configured';

  /// Whether first-run setup has been answered on this device.
  ///
  /// Databases created before this screen existed carry no flag, and must
  /// not be dragged back through setup: one that already holds a
  /// catalogue or a movement is a working installation by definition, so
  /// it is treated as configured and the flag is written once to settle
  /// the question cheaply from then on.
  Future<bool> isCompanyConfigured() async {
    final db = await _db;
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [_configuredKey],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['value'] == '1';

    final inUse =
        await _hasAny(db, 'products') || await _hasAny(db, 'stock_entries');
    if (inUse) await markCompanyConfigured();
    return inUse;
  }

  /// Records that the question has been answered -- including when the
  /// operator chose to skip and take their magasins from a sync instead.
  Future<void> markCompanyConfigured() async {
    final db = await _db;
    await db.insert(
      'sync_meta',
      {'key': _configuredKey, 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> _hasAny(Database db, String table) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $table'),
    );
    return (count ?? 0) > 0;
  }
}
