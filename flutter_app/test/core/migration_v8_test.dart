import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';

/// Les mouvements gagnent un auteur.
///
/// Ce que la migration doit **refuser** de faire est plus important que
/// ce qu'elle fait : attribuer les mouvements déjà au dossier au premier
/// administrateur venu serait signer à sa place, et une signature fausse
/// vaut moins que pas de signature du tout.
Future<Database> _baseV7() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 7, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, '
    "password_salt TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'magasinier')",
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
  await db.execute(
    'CREATE TABLE transferts (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'date TEXT NOT NULL, source_id INTEGER NOT NULL, '
    'destination_id INTEGER NOT NULL, notes TEXT)',
  );
  await db.insert('users', {
    'username': 'patron',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'admin',
  });
  await db.insert('stock_entries', {
    'date': '2026-01-05',
    'supplier': 'SONECOMX',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'store_id': 1,
    'quantity': 40,
  });
  await db.insert('stock_outputs', {
    'date': '2026-01-08',
    'reference': 'RIZ25',
    'designation': 'RIZ',
    'store_id': 1,
    'destination': 'BMC',
    'quantity': 10,
  });
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV7ToV8) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV7());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    expect((await db.query('stock_entries')).single['quantity'], 40);
    expect((await db.query('stock_outputs')).single['destination'], 'BMC');
  });

  test('aucun mouvement existant ne se voit attribuer un auteur', () async {
    // Il y a un administrateur en base et un seul : le désigner comme
    // auteur de tout l'historique serait le geste tentant et le faux.
    // « Auteur inconnu » est la vérité sur ces lignes-là.
    await _migrer(db);

    expect((await db.query('stock_entries')).single['created_by'], isNull);
    expect((await db.query('stock_outputs')).single['created_by'], isNull);
  });

  test("ni une heure d'écriture rétroactive", () async {
    // Inscrire `now()` prétendrait que ces lignes ont été saisies au
    // moment de la mise à jour, ce qui est faux pour toutes.
    await _migrer(db);

    expect((await db.query('stock_entries')).single['created_at'], isNull);
    expect((await db.query('stock_outputs')).single['created_at'], isNull);
  });

  test("les transferts reçoivent les mêmes colonnes", () async {
    await _migrer(db);

    final id = await db.insert('transferts', {
      'date': '2026-02-01',
      'source_id': 1,
      'destination_id': 2,
      'created_by': 1,
      'created_at': '2026-02-01T08:00:00.000Z',
    });

    expect((await db.query('transferts', where: 'id = ?', whereArgs: [id]))
        .single['created_by'], 1);
  });

  test('un mouvement écrit après la migration peut être signé', () async {
    await _migrer(db);

    await db.insert('stock_entries', {
      'date': '2026-02-01',
      'supplier': 'SONECOMX',
      'reference': 'RIZ25',
      'designation': 'RIZ',
      'store_id': 1,
      'quantity': 5,
      'created_by': 1,
      'created_at': '2026-02-01T08:00:00.000Z',
    });

    final signes = await db.query('stock_entries',
        where: 'created_by IS NOT NULL');
    expect(signes, hasLength(1));
    expect(signes.single['quantity'], 5);
  });
}
