import 'package:sqflite/sqflite.dart';

import '../../auth/password_hasher.dart';
import '../db/database_service.dart';
import '../models/user.dart';

class UserRepository {
  UserRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async => _injectedDb ?? DatabaseService.instance.database;

  Future<bool> hasUsers() async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM users'),
    );
    return (count ?? 0) > 0;
  }

  Future<AppUser?> findByUsername(String username) async {
    final db = await _db;
    final rows = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  Future<AppUser> createUser({
    required String username,
    required String password,
    String role = 'admin',
  }) async {
    final db = await _db;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hash(password, salt);
    final id = await db.insert('users', {
      'username': username,
      'password_hash': hash,
      'password_salt': salt,
      'role': role,
    });
    return AppUser(
      id: id,
      username: username,
      passwordHash: hash,
      passwordSalt: salt,
      role: role,
    );
  }

  Future<AppUser?> authenticate(String username, String password) async {
    final user = await findByUsername(username);
    if (user == null) return null;
    final ok = PasswordHasher.verify(password, user.passwordSalt, user.passwordHash);
    return ok ? user : null;
  }

  /// All accounts, used by the admin-only "Gestion des utilisateurs" panel.
  Future<List<AppUser>> getAllUsers() async {
    final db = await _db;
    final rows = await db.query('users', orderBy: 'username');
    return rows.map(AppUser.fromMap).toList();
  }

  /// Number of accounts with the 'admin' role, used to prevent demoting or
  /// deleting the last remaining administrator.
  Future<int> countAdmins() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM users WHERE role = 'admin'"),
        ) ??
        0;
  }

  Future<void> updateRole(int id, String role) async {
    final db = await _db;
    await db.update('users', {'role': role}, where: 'id = ?', whereArgs: [id]);
  }

  /// Generates a new salt/hash pair for [newPassword] and returns the
  /// updated user. Used both for self-service password changes and for
  /// admin password resets.
  Future<AppUser> updatePassword(int id, String newPassword) async {
    final db = await _db;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hash(newPassword, salt);
    await db.update(
      'users',
      {'password_hash': hash, 'password_salt': salt},
      where: 'id = ?',
      whereArgs: [id],
    );
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return AppUser.fromMap(rows.first);
  }

  Future<void> deleteUser(int id) async {
    final db = await _db;
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }
}
