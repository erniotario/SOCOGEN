import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/auth/permissions.dart';
import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/core/db/sync_columns.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/shared/models/role.dart';

/// Les rôles et les droits qu'on leur accorde.
class RoleRepository {
  RoleRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  Future<List<Role>> getAll() async {
    final db = await _db;
    final rows = await db.query('roles', orderBy: 'integre DESC, libelle');
    return rows.map(Role.fromMap).toList();
  }

  Future<Role?> getByCode(String code) async {
    final db = await _db;
    final rows =
        await db.query('roles', where: 'code = ?', whereArgs: [code], limit: 1);
    return rows.isEmpty ? null : Role.fromMap(rows.first);
  }

  /// Les codes de permission accordés à un rôle.
  ///
  /// L'administrateur n'a volontairement aucune ligne : il répond oui à
  /// tout par construction, et lui en donner permettrait de lui retirer
  /// le droit de gérer les droits. La réponse est donc vide pour lui, et
  /// [PermissionGate] ne la consulte même pas.
  Future<Set<String>> droitsDe(String roleCode) async {
    final db = await _db;
    final rows = await db.query(
      'role_permissions',
      columns: ['permission_code'],
      where: 'role_code = ?',
      whereArgs: [roleCode],
    );
    return rows.map((r) => r['permission_code'] as String).toSet();
  }

  /// Remplace d'un bloc les droits d'un rôle.
  ///
  /// En une transaction, et par remplacement plutôt que par différence :
  /// l'écran envoie l'état complet des cases cochées, et une écriture
  /// partielle laisserait un rôle avec un mélange d'avant et d'après.
  Future<void> definirDroits(String roleCode, Set<String> codes) async {
    if (roleCode == PermissionGate.roleAdmin) {
      throw const ErreurUtilisateur(
        "Les droits de l'administrateur ne se modifient pas : il peut "
        'tout, et c'
        "'est ce qui garantit qu'un compte puisse toujours rendre les "
        'droits aux autres.',
      );
    }
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('role_permissions',
          where: 'role_code = ?', whereArgs: [roleCode]);
      for (final code in codes) {
        await txn.insert('role_permissions', {
          'role_code': roleCode,
          'permission_code': code,
          'updated_at': nowIso(),
        });
      }
    });
  }

  Future<void> creer(Role role) async {
    final db = await _db;
    if (role.code.trim().isEmpty || role.libelle.trim().isEmpty) {
      throw const ErreurUtilisateur('Le code et le libellé sont obligatoires.');
    }
    if (await getByCode(role.code) != null) {
      throw ErreurUtilisateur('Le rôle « ${role.code} » existe déjà.');
    }
    await db.insert('roles', {
      ...role.toMap(),
      'sync_id': newSyncId(),
      'updated_at': nowIso(),
    });
  }

  Future<void> renommer(String code, String libelle) async {
    final db = await _db;
    await db.update(
      'roles',
      {'libelle': libelle.trim(), 'updated_at': nowIso()},
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  /// Combien de comptes portent ce rôle.
  Future<int> compterComptes(String roleCode) async {
    final db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM users WHERE role = ?',
          [roleCode],
        )) ??
        0;
  }

  /// Supprime un rôle, à trois conditions.
  ///
  /// Un rôle **intégré** ne s'efface pas : sans `admin` plus personne ne
  /// rend de droits, et sans `magasinier` les comptes créés avec le rôle
  /// par défaut de la table `users` pointeraient dans le vide. Un rôle
  /// **porté par des comptes** non plus — ces comptes se retrouveraient
  /// sans aucun droit du jour au lendemain.
  Future<void> supprimer(String code) async {
    final role = await getByCode(code);
    if (role == null) {
      throw const ErreurUtilisateur('Rôle introuvable.');
    }
    if (role.integre) {
      throw ErreurUtilisateur(
        'Le rôle « ${role.libelle} » fait partie de l\'application et ne '
        'peut pas être supprimé.',
      );
    }
    final comptes = await compterComptes(code);
    if (comptes > 0) {
      throw ErreurUtilisateur(
        '$comptes compte${comptes > 1 ? 's' : ''} '
        'utilise${comptes > 1 ? 'nt' : ''} encore le rôle '
        '« ${role.libelle} ». Changez-leur de rôle avant de le supprimer.',
      );
    }
    final db = await _db;
    await db.delete('roles', where: 'code = ?', whereArgs: [code]);
  }
}
