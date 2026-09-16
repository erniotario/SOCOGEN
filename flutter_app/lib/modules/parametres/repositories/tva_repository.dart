import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/core/db/sync_columns.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/modules/parametres/models/taux_tva.dart';

/// Les taux de TVA de l'entreprise.
class TvaRepository {
  TvaRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Tous les taux, du plus faible au plus élevé.
  ///
  /// L'ordre n'est pas cosmétique : dans une liste déroulante, l'exonéré
  /// en tête évite de le chercher, et c'est le cas le plus fréquent chez
  /// un grossiste alimentaire.
  Future<List<TauxTva>> getAll() async {
    final db = await _db;
    final rows = await db.query('taux_tva', orderBy: 'pour_dix_mille, libelle');
    return rows.map(TauxTva.fromMap).toList();
  }

  Future<TauxTva?> getById(int id) async {
    final db = await _db;
    final rows =
        await db.query('taux_tva', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : TauxTva.fromMap(rows.first);
  }

  /// Le taux proposé à la création d'un article, ou null s'il n'y en a
  /// aucun — une base vidée à la main, par exemple.
  Future<TauxTva?> getDefaut() async {
    final db = await _db;
    final rows = await db.query(
      'taux_tva',
      where: 'is_defaut = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : TauxTva.fromMap(rows.first);
  }

  Future<int> create({
    required String code,
    required String libelle,
    required int pourDixMille,
  }) async {
    if (pourDixMille < 0) {
      throw const ErreurUtilisateur('Un taux de TVA ne peut pas être négatif.');
    }
    final db = await _db;
    return db.insert('taux_tva', {
      'code': code,
      'libelle': libelle,
      'pour_dix_mille': pourDixMille,
      'is_defaut': 0,
      'updated_at': nowIso(),
    });
  }

  Future<void> update(TauxTva taux) async {
    final db = await _db;
    final values = taux.toMap(includeId: false);
    values['updated_at'] = nowIso();
    await db.update('taux_tva', values,
        where: 'id = ?', whereArgs: [taux.id]);
  }

  /// Désigne [id] comme taux par défaut, et retire ce statut aux autres.
  ///
  /// Les deux écritures sont dans une transaction : un instant à deux
  /// taux par défaut, ou à aucun, donnerait un article créé entre-temps
  /// avec la mauvaise TVA.
  Future<void> definirDefaut(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('taux_tva', {'is_defaut': 0, 'updated_at': nowIso()});
      await txn.update(
        'taux_tva',
        {'is_defaut': 1, 'updated_at': nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Combien d'articles utilisent ce taux.
  ///
  /// Sert à refuser une suppression qui laisserait des articles sans
  /// TVA plutôt qu'à la faire et à le constater après.
  Future<int> compterArticles(int tvaId) async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM products WHERE tva_id = ?',
            [tvaId],
          ),
        ) ??
        0;
  }

  Future<void> delete(int id) async {
    final utilises = await compterArticles(id);
    if (utilises > 0) {
      throw ErreurUtilisateur(
        'Ce taux est utilisé par $utilises article(s). Changez leur TVA '
        'avant de le supprimer.',
      );
    }
    final db = await _db;
    await db.delete('taux_tva', where: 'id = ?', whereArgs: [id]);
  }
}
