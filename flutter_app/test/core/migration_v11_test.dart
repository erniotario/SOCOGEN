import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';

/// Les règlements arrivent.
///
/// Il n'y a rien à reprendre : aucune vente antérieure n'a été encaissée
/// par cette application, et inventer un règlement pour chacune
/// prétendrait que des tickets ont été payés sans que personne ne l'ait
/// constaté. La table arrive vide, et c'est la vérité.
Future<Database> _baseV10() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 10, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE stock_outputs (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'date TEXT NOT NULL, reference TEXT NOT NULL, designation TEXT NOT NULL, '
    "invoice_number TEXT DEFAULT '', store_id INTEGER NOT NULL, "
    "destination TEXT DEFAULT '', quantity INTEGER NOT NULL, "
    'prix_unitaire INTEGER)',
  );
  await db.insert('stock_outputs', {
    'date': '2026-01-08',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'invoice_number': 'FAC0000542',
    'store_id': 1,
    'destination': 'BMC',
    'quantity': 10,
  });
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV10ToV11) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV10());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    expect((await db.query('stock_outputs')).single['quantity'], 10);
  });

  test('la table des règlements arrive vide', () async {
    // Inventer un règlement par vente passée prétendrait que des
    // tickets ont été payés sans que personne l'ait constaté.
    await _migrer(db);

    expect(await db.query('paiements'), isEmpty);
  });

  test('un règlement peut être écrit juste après', () async {
    await _migrer(db);

    await db.insert('paiements', {
      'ticket': 'TKT0000001',
      'mode': 'especes',
      'montant': 18500,
      'date': '2026-03-01',
    });

    final paiement = (await db.query('paiements')).single;
    expect(paiement['montant'], 18500);
    expect(paiement['mode'], 'especes');
  });

  test('rejouer la migration ne casse rien', () async {
    await _migrer(db);
    await db.insert('paiements', {
      'ticket': 'TKT0000001',
      'mode': 'especes',
      'montant': 500,
      'date': '2026-03-01',
    });

    await _migrer(db);

    expect(await db.query('paiements'), hasLength(1));
  });
}
