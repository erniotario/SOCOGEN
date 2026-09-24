import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';

/// Le taux de TVA rejoint le prix sur la ligne de vente.
///
/// La migration n'attribue **aucun** taux aux lignes existantes. Leur
/// appliquer celui d'aujourd'hui prétendrait savoir ce qui a été
/// facturé alors que personne ne l'a jamais écrit — et une TVA inventée
/// sur une facture est pire qu'une facture qui dit ne pas pouvoir la
/// ventiler. Même refus que l'attribution d'auteur en v8.
Future<Database> _baseV11() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 11, singleInstance: false),
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
    'prix_unitaire': 15900,
  });
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV11ToV12) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV11());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    final ligne = (await db.query('stock_outputs')).single;
    expect(ligne['quantity'], 10);
    expect(ligne['prix_unitaire'], 15900);
  });

  test("les lignes d'avant n'héritent d'aucun taux", () async {
    // Un taux nul n'est pas un taux de zéro : c'est « on ne sait pas »,
    // et la facture doit l'annoncer plutôt que de ventiler une TVA
    // qu'elle aurait inventée.
    await _migrer(db);

    expect((await db.query('stock_outputs')).single['tva_pour_dix_mille'],
        isNull);
  });

  test('une vente écrite après porte son taux', () async {
    await _migrer(db);

    await db.insert('stock_outputs', {
      'date': '2026-03-01',
      'reference': 'RIZ25',
      'designation': 'RIZ',
      'invoice_number': 'TKT0000001',
      'store_id': 1,
      'destination': '',
      'quantity': 1,
      'prix_unitaire': 11925,
      'tva_pour_dix_mille': 1925,
    });

    final ligne = (await db.query('stock_outputs',
            where: 'invoice_number = ?', whereArgs: ['TKT0000001']))
        .single;
    expect(ligne['tva_pour_dix_mille'], 1925);
  });

  test('la colonne accepte un taux nul explicitement', () async {
    // Un article réellement hors champ de la TVA se distingue d'un
    // article dont on ignore le taux : 0 est une décision, nul est une
    // absence.
    await _migrer(db);

    await db.insert('stock_outputs', {
      'date': '2026-03-01',
      'reference': 'LAIT',
      'designation': 'LAIT',
      'invoice_number': 'TKT0000002',
      'store_id': 1,
      'destination': '',
      'quantity': 1,
      'prix_unitaire': 500,
      'tva_pour_dix_mille': 0,
    });

    final ligne = (await db.query('stock_outputs',
            where: 'invoice_number = ?', whereArgs: ['TKT0000002']))
        .single;
    expect(ligne['tva_pour_dix_mille'], 0);
    expect(ligne['tva_pour_dix_mille'], isNotNull);
  });
}
