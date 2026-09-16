import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/modules/utilisateurs/repositories/user_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late UserRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = UserRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('hasUsers and findByUsername reflect an empty users table', () async {
    expect(await repo.hasUsers(), isFalse);
    expect(await repo.findByUsername('admin'), isNull);
  });

  test('createUser hashes the password and authenticate verifies it', () async {
    final user = await repo.createUser(username: 'admin', password: 'secret123');

    expect(await repo.hasUsers(), isTrue);
    // Le condensat porte son algorithme et son coût, et n'est plus un
    // simple SHA-256 hexadécimal de 64 caractères.
    expect(user.passwordHash, startsWith('pbkdf2_sha256\$'));
    expect(user.passwordHash, isNot(matches(RegExp(r'^[0-9a-f]{64}$'))));
    expect(user.passwordSalt.length, 32);
    expect(user.isAdmin, isTrue);

    final found = await repo.findByUsername('admin');
    expect(found, isNotNull);
    expect(found!.passwordHash, user.passwordHash);

    final authenticated = await repo.authenticate('admin', 'secret123');
    expect(authenticated, isNotNull);
    expect(authenticated!.username, 'admin');

    expect(await repo.authenticate('admin', 'wrong-password'), isNull);
    expect(await repo.authenticate('nobody', 'secret123'), isNull);
  });

  test('getAllUsers returns every account ordered by username', () async {
    await repo.createUser(username: 'admin', password: 'secret123');
    await repo.createUser(username: 'bernard', password: 'secret123', role: 'magasinier');

    final users = await repo.getAllUsers();
    expect(users.map((u) => u.username), ['admin', 'bernard']);
  });

  test('countAdmins counts only admin accounts', () async {
    await repo.createUser(username: 'admin', password: 'secret123');
    await repo.createUser(username: 'bernard', password: 'secret123', role: 'magasinier');

    expect(await repo.countAdmins(), 1);

    await repo.createUser(username: 'claire', password: 'secret123');
    expect(await repo.countAdmins(), 2);
  });

  test('updateRole changes an account role', () async {
    final user = await repo.createUser(username: 'bernard', password: 'secret123', role: 'magasinier');

    await repo.updateRole(user.id, 'admin');

    final updated = await repo.findByUsername('bernard');
    expect(updated!.role, 'admin');
    expect(updated.isAdmin, isTrue);
  });

  test('updatePassword changes the hash and salt so the old password fails', () async {
    final user = await repo.createUser(username: 'admin', password: 'secret123');
    final oldHash = user.passwordHash;
    final oldSalt = user.passwordSalt;

    final updated = await repo.updatePassword(user.id, 'newpassword');

    expect(updated.passwordHash, isNot(oldHash));
    expect(updated.passwordSalt, isNot(oldSalt));
    expect(await repo.authenticate('admin', 'secret123'), isNull);
    expect(await repo.authenticate('admin', 'newpassword'), isNotNull);
  });

  test('deleteUser removes the account', () async {
    final user = await repo.createUser(username: 'bernard', password: 'secret123', role: 'magasinier');

    await repo.deleteUser(user.id);

    expect(await repo.findByUsername('bernard'), isNull);
  });

  test('un compte hérité se connecte et repart au format courant', () async {
    // Le cas réel : la base installée chez le client contient des
    // condensats SHA-256 à un tour, et personne ne connaît les mots de
    // passe. La seule occasion de les réécrire est une connexion réussie.
    const sel = 'abcdef0123456789abcdef0123456789';
    final ancien = sha256.convert(utf8.encode('${sel}secret123')).toString();
    await db.insert('users', {
      'username': 'olivier',
      'password_hash': ancien,
      'password_salt': sel,
      'role': 'magasinier',
    });

    final connecte = await repo.authenticate('olivier', 'secret123');
    expect(connecte, isNotNull, reason: 'un compte hérité doit pouvoir entrer');

    final apres = await repo.findByUsername('olivier');
    expect(
      apres!.passwordHash,
      startsWith('pbkdf2_sha256\$'),
      reason: 'le condensat doit avoir été réécrit à la connexion',
    );
    expect(apres.passwordSalt, isNot(sel), reason: 'un nouveau sel est tiré');

    // Et le mot de passe fonctionne toujours, sous la nouvelle forme.
    expect(await repo.authenticate('olivier', 'secret123'), isNotNull);
    expect(await repo.authenticate('olivier', 'mauvais'), isNull);
  });

  test('un mauvais mot de passe ne déclenche aucune réécriture', () async {
    const sel = 'abcdef0123456789abcdef0123456789';
    final ancien = sha256.convert(utf8.encode('${sel}secret123')).toString();
    await db.insert('users', {
      'username': 'olivier',
      'password_hash': ancien,
      'password_salt': sel,
      'role': 'magasinier',
    });

    expect(await repo.authenticate('olivier', 'mauvais'), isNull);

    final apres = await repo.findByUsername('olivier');
    expect(apres!.passwordHash, ancien, reason: 'rien ne doit avoir bougé');
  });

}
