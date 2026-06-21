import 'package:sqflite/sqflite.dart';

import '../db/database_service.dart';
import '../models/company_settings.dart';

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
}
