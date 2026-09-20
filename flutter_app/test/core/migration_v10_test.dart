import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/db/schema.dart';

/// L'argent arrive sur le mouvement.
///
/// Ce que la migration doit refuser : prêter aux 5 201 mouvements déjà
/// au dossier le prix d'aujourd'hui. Cela inventerait un chiffre
/// d'affaires qui n'a jamais été constaté, et le pire est qu'il aurait
/// l'air juste.
Future<Database> _baseV9() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 9, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE stock_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    "date TEXT NOT NULL, supplier TEXT DEFAULT '', reference TEXT NOT NULL, "
    'designation TEXT NOT NULL, store_id INTEGER NOT NULL, '
    'quantity INTEGER NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE stock_outputs (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'date TEXT NOT NULL, reference TEXT NOT NULL, designation TEXT NOT NULL, '
    "invoice_number TEXT DEFAULT '', store_id INTEGER NOT NULL, "
    "destination TEXT DEFAULT '', quantity INTEGER NOT NULL)",
  );
  await db.insert('stock_outputs', {
    'date': '2026-01-08',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'store_id': 1,
    'destination': 'BMC',
    'quantity': 10,
  });
  await db.insert('stock_entries', {
    'date': '2026-01-05',
    'supplier': 'SONECOMX',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'store_id': 1,
    'quantity': 40,
  });
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV9ToV10) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV9());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    expect((await db.query('stock_outputs')).single['quantity'], 10);
    expect((await db.query('stock_entries')).single['supplier'], 'SONECOMX');
  });

  test('aucun mouvement existant ne se voit prêter un prix', () async {
    await _migrer(db);

    expect((await db.query('stock_outputs')).single['prix_unitaire'], isNull);
    expect((await db.query('stock_entries')).single['prix_unitaire'], isNull);
  });

  test('un mouvement écrit après peut porter le sien', () async {
    await _migrer(db);

    await db.insert('stock_outputs', {
      'date': '2026-03-01',
      'reference': 'RIZ25',
      'designation': 'RIZ',
      'store_id': 2,
      'destination': 'Client',
      'quantity': 2,
      'prix_unitaire': 18500,
    });

    final valorisees =
        await db.query('stock_outputs', where: 'prix_unitaire IS NOT NULL');
    expect(valorisees, hasLength(1));
    expect(valorisees.single['prix_unitaire'], 18500);
  });
}
