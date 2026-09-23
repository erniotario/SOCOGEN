import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';

/// Le transfert entre magasins devient une opération.
///
/// La migration n'a rien à reprendre : les déplacements déjà saisis
/// l'ont été comme une sortie et une entrée ordinaires, et **rien dans
/// les données ne dit lesquels allaient ensemble**. Les rapprocher après
/// coup sur la date et la quantité serait deviner, exactement ce que la
/// reprise des tiers a refusé de faire sur les noms. Les anciens
/// mouvements restent donc ce qu'ils sont ; le lien commence
/// aujourd'hui.
Future<Database> _baseV6() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 6, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE stores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)',
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
  await db.insert('stores', {'id': 1, 'name': 'Hysacam'});
  await db.insert('stores', {'id': 2, 'name': 'Ekie'});
  await db.insert('stock_entries', {
    'date': '2026-01-05',
    'supplier': 'SONECOMX',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'store_id': 1,
    'quantity': 40,
  });
  await db.insert('stock_outputs', {
    'date': '2026-01-05',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'store_id': 1,
    'destination': 'BMC',
    'quantity': 10,
  });
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV6ToV7) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV6());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    expect((await db.query('stock_entries')).single['quantity'], 40);
    expect((await db.query('stock_outputs')).single['destination'], 'BMC');
  });

  test('la table des transferts arrive vide', () async {
    await _migrer(db);

    expect(await db.query('transferts'), isEmpty);
  });

  test('aucun mouvement ancien ne se voit attribuer un transfert', () async {
    // Rapprocher après coup une sortie et une entrée sur la date et la
    // quantité serait deviner : deux mouvements du même jour ne sont pas
    // forcément le même déplacement, et une paire inventée ferait
    // disparaître une vraie vente des chiffres.
    await _migrer(db);

    expect((await db.query('stock_entries')).single['transfert_id'], isNull);
    expect((await db.query('stock_outputs')).single['transfert_id'], isNull);
  });

  test('un transfert peut être écrit juste après', () async {
    await _migrer(db);

    final id = await db.insert('transferts', {
      'date': '2026-02-01',
      'source_id': 1,
      'destination_id': 2,
    });
    await db.insert('stock_outputs', {
      'date': '2026-02-01',
      'reference': 'RIZ25',
      'designation': 'RIZ',
      'store_id': 1,
      'destination': 'Transfert vers Ekie',
      'quantity': 5,
      'transfert_id': id,
    });

    final lies = await db.query('stock_outputs',
        where: 'transfert_id IS NOT NULL');
    expect(lies, hasLength(1));
    expect(lies.single['transfert_id'], id);
  });
}
