import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';

/// La clôture comptable arrive.
///
/// La table est **vide**, donc rien n'est fermé. Dater d'office une
/// clôture au dernier exercice verrouillerait des corrections que
/// personne n'a demandé d'interdire, et sur une base dont on ne sait
/// rien ce serait interdire au hasard. Fermer est une décision, et elle
/// se prend — même refus que l'attribution d'auteur en v8 et que le
/// taux de TVA en v12.
Future<Database> _baseV12() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 12, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE stock_outputs (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'date TEXT NOT NULL, reference TEXT NOT NULL, designation TEXT NOT NULL, '
    "invoice_number TEXT DEFAULT '', store_id INTEGER NOT NULL, "
    "destination TEXT DEFAULT '', quantity INTEGER NOT NULL, "
    'prix_unitaire INTEGER, tva_pour_dix_mille INTEGER)',
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
  for (final sql in AppSchema.migrationV12ToV13) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV12());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    expect((await db.query('stock_outputs')).single['quantity'], 10);
  });

  test('aucune période n\'arrive fermée', () async {
    await _migrer(db);

    expect(await db.query('cloture_comptable'), isEmpty);
  });

  test('une clôture peut être posée juste après', () async {
    await _migrer(db);

    await db.insert('cloture_comptable', {
      'ferme_jusquau': '2026-03-31',
      'created_at': '2026-04-02T08:00:00Z',
    });

    final acte = (await db.query('cloture_comptable')).single;
    expect(acte['ferme_jusquau'], '2026-03-31');
    expect(acte['motif'], isNull,
        reason: 'fermer n\'a pas à s\'expliquer, rouvrir si');
  });

  test('les actes s\'empilent au lieu de s\'écraser', () async {
    // « Qui a rouvert mars, et pourquoi » est la question qu'un
    // contrôle pose : une table qui ne garderait que l'état courant ne
    // saurait pas y répondre.
    await _migrer(db);

    await db.insert('cloture_comptable', {'ferme_jusquau': '2026-03-31'});
    await db.insert('cloture_comptable', {
      'ferme_jusquau': '2026-02-28',
      'motif': 'Avoir client oublié',
    });

    final actes = await db.query('cloture_comptable', orderBy: 'id');
    expect(actes, hasLength(2));
    expect(actes.last['motif'], 'Avoir client oublié');
  });

  test('rejouer la migration ne casse rien', () async {
    await _migrer(db);
    await db.insert('cloture_comptable', {'ferme_jusquau': '2026-03-31'});

    await _migrer(db);

    expect(await db.query('cloture_comptable'), hasLength(1));
  });
}
