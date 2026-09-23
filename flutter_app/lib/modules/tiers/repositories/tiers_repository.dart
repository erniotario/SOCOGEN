import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/db/sync_columns.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/shared/models/tiers.dart';

/// Les fiches clients et fournisseurs.
class TiersRepository {
  TiersRepository({Database? database}) : _injectedDb = database;

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Les tiers, par nom.
  ///
  /// [type] filtre sur le rôle : demander les clients rend aussi ceux
  /// qui sont client *et* fournisseur, puisqu'ils le sont réellement.
  Future<List<Tiers>> getAll({TypeTiers? type, bool actifsSeuls = true}) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    if (actifsSeuls) conditions.add('actif = 1');
    if (type != null) {
      conditions.add('(type = ? OR type = ?)');
      args.addAll([type.code, TypeTiers.lesDeux.code]);
    }
    final rows = await db.query(
      'tiers',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'nom',
    );
    return rows.map(Tiers.fromMap).toList();
  }

  Future<Tiers?> getById(int id) async {
    final db = await _db;
    final rows =
        await db.query('tiers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Tiers.fromMap(rows.first);
  }

  Future<Tiers?> getParNom(String nom) async {
    final db = await _db;
    final rows = await db.query('tiers',
        where: 'nom = ?', whereArgs: [nom.trim()], limit: 1);
    return rows.isEmpty ? null : Tiers.fromMap(rows.first);
  }

  /// Recherche sur le nom, le code, le téléphone et le numéro fiscal.
  ///
  /// Quatre colonnes parce qu'un magasinier cherche avec ce qu'il a sous
  /// les yeux : un nom sur un bon, un numéro sur un téléphone.
  Future<List<Tiers>> rechercher(String terme, {TypeTiers? type}) async {
    final t = terme.trim();
    if (t.isEmpty) return getAll(type: type);
    final db = await _db;
    final like = '%$t%';
    final conditions = <String>[
      'actif = 1',
      '(nom LIKE ? OR code LIKE ? OR telephone LIKE ? OR niu LIKE ?)',
    ];
    final args = <Object?>[like, like, like, like];
    if (type != null) {
      conditions.add('(type = ? OR type = ?)');
      args.addAll([type.code, TypeTiers.lesDeux.code]);
    }
    final rows = await db.query(
      'tiers',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'nom',
    );
    return rows.map(Tiers.fromMap).toList();
  }

  /// Le prochain code libre pour [type] : C0001, F0042.
  ///
  /// Calculé à la demande plutôt que stocké dans un compteur : un
  /// compteur se désynchronise d'une base restaurée ou fusionnée, alors
  /// que le maximum observé reste vrai quoi qu'il arrive.
  Future<String> prochainCode(TypeTiers type) async {
    final db = await _db;
    final prefixe = type == TypeTiers.client ? 'C' : 'F';
    final rows = await db.rawQuery(
      "SELECT code FROM tiers WHERE code LIKE ? ORDER BY code DESC LIMIT 1",
      ['$prefixe%'],
    );
    var suivant = 1;
    if (rows.isNotEmpty) {
      final dernier = int.tryParse((rows.first['code'] as String).substring(1));
      if (dernier != null) suivant = dernier + 1;
    }
    return '$prefixe${suivant.toString().padLeft(4, '0')}';
  }

  Future<int> create(Tiers tiers) async {
    if (tiers.nom.trim().isEmpty) {
      throw const ErreurUtilisateur('Le nom du tiers est obligatoire.');
    }
    final db = await _db;
    final values = tiers.toMap(includeId: false);
    values['nom'] = tiers.nom.trim();
    values['sync_id'] = newSyncId();
    values['updated_at'] = nowIso();
    return db.insert('tiers', values);
  }

  Future<void> update(Tiers tiers) async {
    if (tiers.nom.trim().isEmpty) {
      throw const ErreurUtilisateur('Le nom du tiers est obligatoire.');
    }
    final db = await _db;
    final values = tiers.toMap(includeId: false);
    values['nom'] = tiers.nom.trim();
    values['updated_at'] = nowIso();
    await db.update('tiers', values, where: 'id = ?', whereArgs: [tiers.id]);
  }

  /// Combien de mouvements portent ce tiers.
  Future<int> compterMouvements(int tiersId) async {
    final db = await _db;
    final entrees = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_entries WHERE tiers_id = ?',
          [tiersId],
        )) ??
        0;
    final sorties = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM stock_outputs WHERE tiers_id = ?',
          [tiersId],
        )) ??
        0;
    return entrees + sorties;
  }

  /// Désactive un tiers plutôt que de le supprimer.
  ///
  /// Ses mouvements passés le référencent ; l'effacer les laisserait
  /// orphelins — le schéma les détacherait en silence. Un tiers
  /// désactivé disparaît des listes de saisie et reste lisible dans
  /// l'historique.
  Future<void> desactiver(int id) async {
    final db = await _db;
    await db.update(
      'tiers',
      {'actif': 0, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reactiver(int id) async {
    final db = await _db;
    await db.update(
      'tiers',
      {'actif': 1, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Fusionne [sourceId] dans [cibleId] : tous les mouvements de la
  /// source passent à la cible, et la source est désactivée.
  ///
  /// C'est l'opération qui règle « BMC » et « BCM ». Elle est explicite
  /// parce que décider que deux noms désignent le même partenaire est un
  /// jugement humain — la reprise automatique s'est bien gardée de le
  /// faire.
  ///
  /// Le texte d'origine reste sur chaque mouvement : une ligne passée
  /// continue de dire ce qui a été saisi ce jour-là, même après fusion.
  /// C'est voulu, et c'est ce qui rend la fusion relisible plus tard.
  Future<int> fusionner({required int sourceId, required int cibleId}) async {
    if (sourceId == cibleId) {
      throw const ErreurUtilisateur(
        'Impossible de fusionner une fiche avec elle-même.',
      );
    }
    final db = await _db;
    final cible = await getById(cibleId);
    final source = await getById(sourceId);
    if (cible == null || source == null) {
      throw const ErreurUtilisateur('Fiche introuvable.');
    }

    return db.transaction((txn) async {
      final e = await txn.update('stock_entries', {'tiers_id': cibleId},
          where: 'tiers_id = ?', whereArgs: [sourceId]);
      final s = await txn.update('stock_outputs', {'tiers_id': cibleId},
          where: 'tiers_id = ?', whereArgs: [sourceId]);
      await txn.update(
        'tiers',
        {'actif': 0, 'updated_at': nowIso()},
        where: 'id = ?',
        whereArgs: [sourceId],
      );
      return e + s;
    });
  }
}
