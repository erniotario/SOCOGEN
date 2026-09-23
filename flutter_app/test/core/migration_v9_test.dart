import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/auth/permissions.dart';
import 'package:erp/core/db/schema.dart';

/// Les rôles et leurs droits passent du code aux données.
///
/// La seule chose qui compte ici : le jour de la mise à jour, personne
/// ne voit son accès changer. La règle en dur était « l'administrateur
/// peut tout, les autres tout sauf ce qui lui est réservé » ; la reprise
/// la recopie en base, permission par permission.
Future<Database> _baseV8() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 8, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, '
    "password_salt TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'magasinier')",
  );
  await db.insert('users', {
    'username': 'patron',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'admin',
  });
  await db.insert('users', {
    'username': 'awa',
    'password_hash': 'x',
    'password_salt': 'y',
    'role': 'magasinier',
  });
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV8ToV9) {
    await db.execute(sql);
  }
  for (final sql in AppSchema.rolesParDefaut) {
    await db.execute(sql);
  }
  for (final sql in AppSchema.droitsParDefaut()) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV8());
  tearDown(() async => db.close());

  test('les comptes existants gardent leur rôle', () async {
    await _migrer(db);

    final comptes = await db.query('users', orderBy: 'username');
    expect(comptes.first['role'], 'awa' == comptes.first['username']
        ? 'magasinier'
        : 'admin');
    expect(comptes, hasLength(2));
  });

  test('les deux rôles arrivent, intégrés', () async {
    await _migrer(db);

    final roles = await db.query('roles', orderBy: 'code');
    expect(roles.map((r) => r['code']), ['admin', 'magasinier']);
    expect(roles.every((r) => r['integre'] == 1), isTrue);
  });

  test('le magasinier reçoit exactement ses anciens droits', () async {
    await _migrer(db);

    final accordes = (await db.query('role_permissions',
            where: 'role_code = ?', whereArgs: ['magasinier']))
        .map((r) => r['permission_code'])
        .toSet();
    final attendus = {
      for (final p in Permissions.toutes)
        if (!p.adminSeul) p.code,
    };

    expect(accordes, attendus);
  });

  test("l'administrateur ne reçoit aucune ligne", () async {
    // Il répond oui par construction. Des lignes lui permettraient de
    // s'en retirer, et plus personne ne rendrait de droits ensuite.
    await _migrer(db);

    expect(
      await db.query('role_permissions',
          where: 'role_code = ?', whereArgs: ['admin']),
      isEmpty,
    );
  });

  test('rejouer la reprise ne duplique rien', () async {
    await _migrer(db);
    final avant = (await db.query('role_permissions')).length;

    await _migrer(db);

    expect((await db.query('role_permissions')), hasLength(avant));
    expect((await db.query('roles')), hasLength(2));
  });
}
