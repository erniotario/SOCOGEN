import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/modules/catalogue/models/famille.dart';

/// Les familles d'articles.
class FamilleRepository {
  FamilleRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  /// Profondeur maximale de l'arborescence.
  ///
  /// Trois niveaux couvrent « Alimentaire / Boissons / Sodas » et
  /// suffisent à un grossiste. La limite existe surtout pour qu'une
  /// hiérarchie ne devienne pas un labyrinthe que personne ne parcourt.
  static const int profondeurMax = 3;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  Future<List<Famille>> getAll() async {
    final db = await _db;
    final rows = await db.query('familles', orderBy: 'ordre, nom');
    return rows.map(Famille.fromMap).toList();
  }

  Future<Famille?> getById(int id) async {
    final db = await _db;
    final rows =
        await db.query('familles', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Famille.fromMap(rows.first);
  }

  /// Les familles filles directes de [parentId], ou les racines si null.
  Future<List<Famille>> getEnfants(int? parentId) async {
    final db = await _db;
    final rows = await db.query(
      'familles',
      where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?',
      whereArgs: parentId == null ? null : [parentId],
      orderBy: 'ordre, nom',
    );
    return rows.map(Famille.fromMap).toList();
  }

  /// Le chemin depuis la racine jusqu'à [id] inclus.
  ///
  /// Sert à afficher « Alimentaire › Boissons › Sodas » plutôt qu'un nom
  /// isolé qui ne dit pas où l'on se trouve.
  Future<List<Famille>> getChemin(int id) async {
    final chemin = <Famille>[];
    int? courant = id;
    // Borné par la profondeur : une base abîmée par un cycle ne doit pas
    // faire tourner l'application indéfiniment.
    for (var i = 0; i <= profondeurMax && courant != null; i++) {
      final famille = await getById(courant);
      if (famille == null) break;
      chemin.insert(0, famille);
      courant = famille.parentId;
    }
    return chemin;
  }

  Future<int> create({
    required String code,
    required String nom,
    int? parentId,
    int ordre = 0,
  }) async {
    if (parentId != null) {
      final profondeur = (await getChemin(parentId)).length;
      if (profondeur >= profondeurMax) {
        throw const ErreurUtilisateur(
          'Une famille ne peut pas être imbriquée à plus de trois niveaux.',
        );
      }
    }
    final db = await _db;
    return db.insert('familles', {
      'code': code,
      'nom': nom,
      'parent_id': parentId,
      'ordre': ordre,
      'updated_at': nowIso(),
    });
  }

  Future<void> update(Famille famille) async {
    // Une famille qui descend d'elle-même disparaît de l'arborescence et
    // fait boucler tout parcours. Le cas se produit en déplaçant une
    // famille sous l'une de ses propres filles.
    if (famille.parentId != null) {
      final cheminParent = await getChemin(famille.parentId!);
      if (cheminParent.any((f) => f.id == famille.id)) {
        throw const ErreurUtilisateur(
          'Une famille ne peut pas être rangée sous une de ses '
          'sous-familles.',
        );
      }
    }
    final db = await _db;
    final values = famille.toMap(includeId: false);
    values['updated_at'] = nowIso();
    await db.update('familles', values,
        where: 'id = ?', whereArgs: [famille.id]);
  }

  Future<int> compterArticles(int familleId) async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM products WHERE famille_id = ?',
            [familleId],
          ),
        ) ??
        0;
  }

  /// Supprime une famille vide.
  ///
  /// Refuse tant qu'elle contient des articles ou des sous-familles : le
  /// schéma les détacherait silencieusement (`ON DELETE SET NULL`), et un
  /// catalogue qui se déclasse tout seul est difficile à reconstituer.
  Future<void> delete(int id) async {
    final articles = await compterArticles(id);
    if (articles > 0) {
      throw ErreurUtilisateur(
        'Cette famille contient $articles article(s). Déplacez-les avant '
        'de la supprimer.',
      );
    }
    final enfants = await getEnfants(id);
    if (enfants.isNotEmpty) {
      throw ErreurUtilisateur(
        'Cette famille contient ${enfants.length} sous-famille(s). '
        'Supprimez-les d\'abord.',
      );
    }
    final db = await _db;
    await db.delete('familles', where: 'id = ?', whereArgs: [id]);
  }
}
